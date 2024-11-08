use starknet::ContractAddress;

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct ParkingLot {
    pub lot_id: u256,
    pub name: felt252,
    pub location: felt252,
    pub coordinates: felt252,
    pub slot_count: u32,
    pub hourly_rate_usd_cents: u32,
    pub creator: ContractAddress,
    pub wallet_address: ContractAddress,
    pub is_active: bool,
    pub registration_time: u64
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Booking {
    pub license_plate: felt252, // Vehicle license plate number
    pub booking_id: felt252, // Unique identifier for the booking
    pub lot_id: u256, // Associated parking lot
    pub entry_time: u64, // Timestamp of entry
    pub exit_time: u64, // Timestamp of exit
    pub expiration_time: u64, // Timestamp indicating when the booking expires
    pub total_payment: u64, // Total payment amount in cents
    pub payer: ContractAddress // Wallet address of the user
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Pair {
    token_address: ContractAddress,
    pair_id: felt252,
    pair_decimals: u8,
    token_decimals: u8
}

#[starknet::interface]
pub trait IParking<TContractState> {
    // Register a new parking lot
    fn register_parking_lot(
        ref self: TContractState,
        name: felt252,
        location: felt252,
        coordinates: felt252,
        slot_count: u32,
        hourly_rate_usd_cents: u32, // 100 = $1
        wallet_address: ContractAddress
    );

    // Create a booking for a parking spot
    fn book_parking(
        ref self: TContractState,
        booking_id: felt252,
        lot_id: u256,
        payment_token: ContractAddress,
        license_plate: felt252,
        duration: u32, // Duration in hours
    );

    // End a parking session
    fn end_parking(ref self: TContractState, booking_id: felt252);

    // Extend a parking session
    fn extend_parking(
        ref self: TContractState,
        booking_id: felt252,
        additional_hours: u32,
        payment_token: ContractAddress
    );

    // Impose a penalty on a license plate for invalid parking
    fn impose_penalty(
        ref self: TContractState, license_plate: felt252, lot_id: u256, amount_usd_cents: u64
    );

    // Add a new supported payment token
    fn add_supported_token(
        ref self: TContractState,
        payment_token: ContractAddress,
        pair_id: felt252,
        pair_decimals: u8,
        token_decimals: u8
    );

    // Retrieves the total number of parking lots registered
    fn get_total_parking_lots(self: @TContractState) -> u256;

    // Checks if the given payment token is valid
    fn is_supported_payment_token(self: @TContractState, payment_token: ContractAddress) -> Pair;

    // Get parking lot by lot_id
    fn get_parking_lot(self: @TContractState, lot_id: u256) -> ParkingLot;

    // Get available slots in a parking lot
    fn get_available_slots(self: @TContractState, lot_id: u256) -> u32;

    // Retrieves the booking details for the specified booking ID.
    fn get_booking(self: @TContractState, booking_id: felt252) -> Booking;

    // Retrieves the booking ID of the latest booking associated with the given license plate.
    fn get_latest_booking_by_license_plate(
        self: @TContractState, license_plate: felt252
    ) -> felt252;

    // Validate if the vehicle license plate is valid for the given lot
    fn validate_license_plate(self: @TContractState, lot_id: u256, license_plate: felt252) -> bool;

    // Check for outstanding penalties for a license plate
    fn has_outstanding_penalty(self: @TContractState, license_plate: felt252) -> bool;

    // Retrieves the estimated token amount for a parking spot based on the lot ID and duration
    // using an oracle.
    fn get_oracle_token_quote(
        self: @TContractState,
        lot_id: u256,
        payment_token: ContractAddress,
        duration: u32, // Duration in hours
    ) -> u256;

    // Get asset price using Pragma
    fn get_asset_price(self: @TContractState, asset_id: felt252) -> u128;
}

#[starknet::contract]
pub mod Parking {
    use super::IParking;
    use core::num::traits::Zero;
    use super::{ParkingLot, Booking, Pair};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{Map, StoragePointerWriteAccess,};
    use starkparking_contract::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    // Openzeppelin Lib
    use openzeppelin::security::PausableComponent;
    use openzeppelin::access::ownable::OwnableComponent;

    // Pragma Lib
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{DataType, PragmaPricesResponse};

    // Alexandria math
    use alexandria_math::const_pow::{pow10_u256};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        pragma_contract: ContractAddress, // Pragma Contract Address
        parking_lots: Map::<u256, ParkingLot>, // Mapping from lot_id to ParkingLot
        bookings: Map::<felt252, Booking>, // Mapping from booking_id to Booking
        available_slots: Map::<u256, u32>, // Mapping from lot_id to available slots
        license_plate_to_booking: Map::<felt252, felt252>, // License_plate to booking_id
        penalties: Map::<felt252, u64>, // Mapping from license_plate to penalty_amount
        payment_tokens: Map::<ContractAddress, Pair>,
        total_parking_lots: u256 // Count of total parking lots
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, pragma_contract: ContractAddress
    ) {
        assert(Zero::is_non_zero(@owner), 'Owner address zero');
        assert(Zero::is_non_zero(@pragma_contract), 'Pragma contract address zero');
        self.ownable.initializer(owner);
        self.total_parking_lots.write(0);
        self.pragma_contract.write(pragma_contract);
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        ParkingLotRegistered: ParkingLotRegistered,
        ParkingBooked: ParkingBooked,
        ParkingExtended: ParkingExtended,
        ParkingEnded: ParkingEnded,
        PenaltyImposed: PenaltyImposed,
        PaymentTokenAdded: PaymentTokenAdded,
    }

    // Event for registering a parking lot
    #[derive(Drop, Serde, starknet::Event)]
    struct ParkingLotRegistered {
        lot_id: u256,
    }

    // Event for booking a parking spot
    #[derive(Drop, starknet::Event)]
    struct ParkingBooked {
        booking_id: felt252,
        lot_id: u256,
        entry_time: u64,
        license_plate: felt252,
        duration: u32
    }

    // Event for extending a parking booking
    #[derive(Drop, starknet::Event)]
    struct ParkingExtended {
        booking_id: felt252,
        additional_hours: u32,
    }

    // Event for ending a parking session
    #[derive(Drop, starknet::Event)]
    struct ParkingEnded {
        booking_id: felt252,
        exit_time: u64,
        total_payment: u64
    }

    // Event for imposing a penalty
    #[derive(Drop, starknet::Event)]
    struct PenaltyImposed {
        license_plate: felt252,
        lot_id: u256,
        penalty_amount: u64,
        timestamp: u64,
    }

    // Event for new payment token
    #[derive(Drop, starknet::Event)]
    struct PaymentTokenAdded {
        payment_token: ContractAddress,
        timestamp: u64,
    }

    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.pause();
    }

    #[external(v0)]
    fn unpause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.unpause();
    }

    #[abi(embed_v0)]
    impl ParkingImpl of super::IParking<ContractState> {
        fn register_parking_lot(
            ref self: ContractState,
            name: felt252,
            location: felt252,
            coordinates: felt252,
            slot_count: u32,
            hourly_rate_usd_cents: u32,
            wallet_address: ContractAddress
        ) {
            self.pausable.assert_not_paused();
            assert(Zero::is_non_zero(@wallet_address), 'Wallet address zero');
            assert(slot_count > 0, 'Slot count must be non-zero');
            assert(hourly_rate_usd_cents > 0, 'Price must be non-zero');
            let creator = get_caller_address();
            let total_parking_lots = self.get_total_parking_lots();
            let lot_id: u256 = total_parking_lots + 1;
            let registration_time = get_block_timestamp();
            let new_parking_lot = ParkingLot {
                lot_id,
                name,
                location,
                coordinates,
                slot_count,
                hourly_rate_usd_cents,
                creator,
                wallet_address,
                is_active: true,
                registration_time
            };
            self.parking_lots.write(lot_id, new_parking_lot);
            self.total_parking_lots.write(total_parking_lots + 1);
            self.available_slots.write(lot_id, slot_count);
            self.emit(ParkingLotRegistered { lot_id });
        }

        fn book_parking(
            ref self: ContractState,
            booking_id: felt252,
            lot_id: u256,
            payment_token: ContractAddress,
            license_plate: felt252,
            duration: u32, // Duration in hours
        ) {
            self.pausable.assert_not_paused();
            assert(
                self.is_supported_payment_token(payment_token).token_address == payment_token,
                'Invalid token'
            );
            assert(duration > 0, 'Duration must be non-zero');
            let existing_parking_lot = self.parking_lots.read(lot_id);
            assert(existing_parking_lot.lot_id == lot_id, 'Parking lot does not exist');
            assert(
                self.has_outstanding_penalty(license_plate) == false, 'License plate is penalized'
            );
            let available_slot = self.available_slots.read(lot_id);
            assert(available_slot > 0, 'Full slot');

            let amount = self.get_oracle_token_quote(lot_id, payment_token, duration)
                * duration.into();
            let entry_time = get_block_timestamp();
            let expiration_time = entry_time + (3600 * duration.into());
            let payer = get_caller_address();
            let erc20 = IERC20Dispatcher { contract_address: payment_token };
            let total_payment: u64 = (existing_parking_lot.hourly_rate_usd_cents * duration).into();

            let booking = Booking {
                license_plate,
                booking_id,
                lot_id,
                entry_time,
                exit_time: 0,
                expiration_time,
                total_payment,
                payer
            };

            self.bookings.write(booking_id, booking);
            self.available_slots.write(lot_id, available_slot - 1);
            self.license_plate_to_booking.write(license_plate, booking_id);
            erc20.transferFrom(payer, existing_parking_lot.wallet_address, amount.into());
            self.emit(ParkingBooked { booking_id, lot_id, entry_time, license_plate, duration });
        }

        // End a parking session
        fn end_parking(ref self: ContractState, booking_id: felt252) {
            self.pausable.assert_not_paused();
            let booking = self.bookings.read(booking_id);
            assert(booking.booking_id == booking_id, 'Booking id does not exist');
            let caller = get_caller_address();
            assert(booking.payer == caller, 'Not driver owner');
            // TODO: add pay if over time
            let exit_time = get_block_timestamp();
            let end_booking = Booking {
                license_plate: booking.license_plate,
                booking_id: booking.booking_id,
                lot_id: booking.lot_id,
                entry_time: booking.entry_time,
                exit_time,
                expiration_time: booking.expiration_time,
                total_payment: booking.total_payment,
                payer: caller,
            };
            self.bookings.write(booking_id, end_booking);
            self.emit(ParkingEnded { booking_id, exit_time, total_payment: booking.total_payment });
        }

        // Extend a parking session
        fn extend_parking(
            ref self: ContractState,
            booking_id: felt252,
            additional_hours: u32,
            payment_token: ContractAddress
        ) {
            self.pausable.assert_not_paused();
            assert(additional_hours > 0, 'Duration must be non-zero');
            let booking = self.bookings.read(booking_id);
            assert(booking.booking_id == booking_id, 'Booking ID does not exist');
            assert(
                self.is_supported_payment_token(payment_token).token_address == payment_token,
                'Invalid token'
            );
            let caller = get_caller_address();
            assert(booking.payer == caller, 'Not driver owner');
            let existing_parking_lot = self.parking_lots.read(booking.lot_id);
            assert(existing_parking_lot.lot_id == booking.lot_id, 'Parking lot does not exist');

            let amount = self
                .get_oracle_token_quote(
                    existing_parking_lot.lot_id, payment_token, additional_hours
                )
                * additional_hours.into();
            let expiration_time = booking.expiration_time + (3600 * additional_hours.into());
            let payer = get_caller_address();
            let erc20 = IERC20Dispatcher { contract_address: payment_token };
            let total_payment: u64 = booking.total_payment
                + (existing_parking_lot.hourly_rate_usd_cents * additional_hours).into();

            let extend_booking = Booking {
                license_plate: booking.license_plate,
                booking_id: booking.booking_id,
                lot_id: booking.lot_id,
                entry_time: booking.entry_time,
                exit_time: 0,
                expiration_time,
                total_payment,
                payer
            };
            self.bookings.write(booking_id, extend_booking);
            erc20.transferFrom(payer, existing_parking_lot.wallet_address, amount.into());
            self.emit(ParkingExtended { booking_id, additional_hours });
        }

        // Impose a penalty on a license plate for invalid parking
        fn impose_penalty(
            ref self: ContractState, license_plate: felt252, lot_id: u256, amount_usd_cents: u64
        ) {
            self.pausable.assert_not_paused();
            let existing_parking_lot = self.parking_lots.read(lot_id);
            assert(existing_parking_lot.lot_id == lot_id, 'Parking lot does not exist');
            let caller = get_caller_address();
            assert(existing_parking_lot.creator == caller, 'Not parking lot creator');
            let timestamp = get_block_timestamp();
            self.penalties.write(license_plate, amount_usd_cents);
            self
                .emit(
                    PenaltyImposed {
                        license_plate, lot_id, penalty_amount: amount_usd_cents, timestamp
                    }
                );
        }

        // Add a new supported payment token
        fn add_supported_token(
            ref self: ContractState,
            payment_token: ContractAddress,
            pair_id: felt252,
            pair_decimals: u8,
            token_decimals: u8
        ) {
            self.pausable.assert_not_paused();
            self.ownable.assert_only_owner();
            assert(Zero::is_non_zero(@payment_token), 'Payment token address zero');
            assert(Zero::is_non_zero(@pair_decimals), 'Pair decimals must be non-zero');
            assert(Zero::is_non_zero(@token_decimals), 'Decimals must be non-zero');
            let timestamp = get_block_timestamp();
            let new_token = Pair {
                token_address: payment_token, pair_id, pair_decimals, token_decimals
            };
            self.payment_tokens.write(payment_token, new_token);
            self.emit(PaymentTokenAdded { payment_token, timestamp });
        }

        // Retrieves the total number of parking lots registered
        fn get_total_parking_lots(self: @ContractState) -> u256 {
            self.total_parking_lots.read()
        }

        // Checks if the given payment token is valid
        fn is_supported_payment_token(
            self: @ContractState, payment_token: ContractAddress
        ) -> Pair {
            self.payment_tokens.read(payment_token)
        }

        // Get parking lot by lot_id
        fn get_parking_lot(self: @ContractState, lot_id: u256) -> ParkingLot {
            self.parking_lots.read(lot_id)
        }

        // Get available slots in a parking lot
        fn get_available_slots(self: @ContractState, lot_id: u256) -> u32 {
            self.available_slots.read(lot_id)
        }

        // Retrieves the booking details for the specified booking ID
        fn get_booking(self: @ContractState, booking_id: felt252) -> Booking {
            self.bookings.read(booking_id)
        }

        // Retrieves the booking ID of the latest booking associated with the given license plate
        fn get_latest_booking_by_license_plate(
            self: @ContractState, license_plate: felt252
        ) -> felt252 {
            self.license_plate_to_booking.read(license_plate)
        }

        // Validate if the vehicle license plate is valid for the given lot
        fn validate_license_plate(
            self: @ContractState, lot_id: u256, license_plate: felt252
        ) -> bool {
            let existing_license_plate = self.license_plate_to_booking.read(license_plate);
            match existing_license_plate {
                0 => false,
                _ => {
                    let block_time = get_block_timestamp();
                    let booking = self.bookings.read(existing_license_plate);
                    if (booking.expiration_time > block_time && booking.lot_id == lot_id) {
                        true
                    } else {
                        false
                    }
                }
            }
        }

        // Check for outstanding penalties for a license plate
        fn has_outstanding_penalty(self: @ContractState, license_plate: felt252) -> bool {
            let penalty = self.penalties.read(license_plate);
            match penalty {
                0 => false,
                _ => true
            }
        }

        // Retrieves the estimated token amount for a parking spot based on the lot ID and duration
        // using an oracle.
        fn get_oracle_token_quote(
            self: @ContractState,
            lot_id: u256,
            payment_token: ContractAddress,
            duration: u32, // Duration in hours
        ) -> u256 {
            let token_support = self.is_supported_payment_token(payment_token);
            assert(token_support.token_address == payment_token, 'Invalid token');
            assert(duration > 0, 'Duration must be non-zero');

            let existing_parking_lot = self.parking_lots.read(lot_id);
            assert(existing_parking_lot.lot_id == lot_id, 'Parking lot does not exists');
            // Get asset price
            let token_price = self.get_asset_price(token_support.pair_id).into();

            // Calculate the amount of token needed
            let token_needed = (existing_parking_lot.hourly_rate_usd_cents.into()
                * pow10_u256(token_support.pair_decimals.into())
                * pow10_u256(token_support.token_decimals.into()))
                / (token_price * 100);

            let amount: u256 = token_needed * duration.into();
            amount
        }

        // Retrieve the oracle
        fn get_asset_price(self: @ContractState, asset_id: felt252) -> u128 {
            // Retrieve the oracle dispatcher
            let oracle_dispatcher = IPragmaABIDispatcher {
                contract_address: self.pragma_contract.read()
            };

            // Call the Oracle contract, for a spot entry
            let output: PragmaPricesResponse = oracle_dispatcher
                .get_data_median(DataType::SpotEntry(asset_id));

            output.price
        }
    }
}
