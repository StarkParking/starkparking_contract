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

    // Get available slots in a parking lot
    fn get_available_slots(self: @TContractState, lot_id: u256) -> u32;

    // Validate if the vehicle license plate is valid for the given lot
    fn validate_license_plate(self: @TContractState, lot_id: u256, license_plate: felt252) -> bool;
}

#[starknet::contract]
pub mod Parking {
    use core::num::traits::Zero;
    use super::{ParkingLot, Booking};
    use starknet::{ContractAddress};
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
        ) {}

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
