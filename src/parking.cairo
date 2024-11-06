use starknet::ContractAddress;

#[derive(Drop, Clone, Serde, starknet::Store)]
pub struct ParkingLot {
    lot_id: u256,
    name: felt252,
    location: felt252,
    coordinates: felt252,
    slot_count: u32,
    hourly_rate_usd_cents: u32,
    creator: ContractAddress,
    wallet_address: ContractAddress,
    is_active: bool,
    registration_time: u64
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Booking {
    license_plate: felt252, // Vehicle license plate number
    booking_id: felt252, // Unique identifier for the booking
    lot_id: u256, // Associated parking lot
    entry_time: u64, // Timestamp of entry
    exit_time: u64, // Timestamp of exit
    expiration_time: u64, // Timestamp indicating when the booking expires
    total_payment: u64, // Total payment amount in cents
    payer: ContractAddress // Wallet address of the user
}

#[starknet::interface]
pub trait IParking<TContractState> {
    // Register a new parking lot
    fn register_parking_lot(
        ref self: TContractState,
        lot_id: u256,
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

    // Get a valid payment token
    fn get_payment_token(self: @TContractState) -> ContractAddress;

    // Get parking lot by lot_id
    fn get_parking_lot(self: @TContractState, lot_id: u256) -> ParkingLot;

    // Get available slots in a parking lot
    fn get_available_slots(self: @TContractState, lot_id: u256) -> u32;

    // Validate if the vehicle license plate is valid for the given lot
    fn validate_license_plate(self: @TContractState, lot_id: u256, license_plate: felt252) -> bool;
}

#[starknet::contract]
pub mod Parking {
    use core::num::traits::Zero;
    use super::{ParkingLot, Booking};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{Map, StoragePointerWriteAccess,};

    #[storage]
    struct Storage {
        parking_lots: Map::<u256, ParkingLot>, // Mapping from lot_id to ParkingLot
        bookings: Map::<felt252, Booking>, // Mapping from booking_id to Booking
        available_slots: Map::<u256, u32>, // Mapping from lot_id to available slots
        payment_token: ContractAddress, // TODO: remove it
        license_plate_to_booking: Map::<felt252, felt252> // License_plate to booking_id
    }

    #[constructor]
    fn constructor(ref self: ContractState, payment_token: ContractAddress) {
        assert(Zero::is_non_zero(@payment_token), 'Payment token address zero');
        self.payment_token.write(payment_token); // TODO: remove it
    }

    #[abi(embed_v0)]
    impl ParkingImpl of super::IParking<ContractState> {
        fn register_parking_lot(
            ref self: ContractState,
            lot_id: u256,
            name: felt252,
            location: felt252,
            coordinates: felt252,
            slot_count: u32,
            hourly_rate_usd_cents: u32,
            wallet_address: ContractAddress
        ) {
            let existing_parking_lot = self.parking_lots.read(lot_id);
            assert(existing_parking_lot.lot_id != lot_id, 'lot_id already exists');
            assert(Zero::is_non_zero(@wallet_address), 'Wallet address zero');
            assert(slot_count > 0, 'Slot count must be non-zero');
            assert(hourly_rate_usd_cents > 0, 'Price must be non-zero');
            let creator = get_caller_address();
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
            self.available_slots.write(lot_id, slot_count);
        }

        fn book_parking(
            ref self: ContractState,
            booking_id: felt252,
            lot_id: u256,
            payment_token: ContractAddress,
            license_plate: felt252,
            duration: u32, // Duration in hours
        ) {}

        // End a parking session
        fn end_parking(ref self: ContractState, booking_id: felt252) {}

        // Extend a parking session
        fn extend_parking(
            ref self: ContractState,
            booking_id: felt252,
            additional_hours: u32,
            payment_token: ContractAddress
        ) {}

        // Get a valid payment token
        fn get_payment_token(self: @ContractState) -> ContractAddress {
            self.payment_token.read()
        }

        // Get parking lot by lot_id
        fn get_parking_lot(self: @ContractState, lot_id: u256) -> ParkingLot {
            self.parking_lots.read(lot_id)
        }

        // Get available slots in a parking lot
        fn get_available_slots(self: @ContractState, lot_id: u256) -> u32 {
            30 // TODO: remove it
        }

        // Validate if the vehicle license plate is valid for the given lot
        fn validate_license_plate(
            self: @ContractState, lot_id: u256, license_plate: felt252
        ) -> bool {
            true // TODO: remove it
        }
    }
}
