use starknet::{ContractAddress, contract_address_const};

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

use starkparking_contract::parking::{
    IParkingDispatcher,
    IParkingDispatcherTrait, // IParkingSafeDispatcher, IParkingSafeDispatcherTrait
};

fn default_owner() -> ContractAddress {
    contract_address_const::<0xa4e2d14481b49ce6376e3ca8412df5214225750ecd9e7c9f887904d436e811>()
}

fn pragma_contract() -> ContractAddress {
    contract_address_const::<0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a>()
}

fn default_payment_token() -> ContractAddress {
    contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>()
}

fn default_wallet_address() -> ContractAddress {
    contract_address_const::<0xa4e2d14481b49ce6376e3ca8412df5214225750ecd9e7c9f887904d436e811>()
}

const CONTRACT_ADDRESS: felt252 = 0x7573b8bf44e29c68d5a535972ddf5bf5d17ebbbc4ed075ac602b7ebc5a57819;

// impl ParkingLotDisplay of Display<ParkingLot> {
//     fn fmt(self: @ParkingLot, ref f: Formatter) -> Result<(), Error> {
//         let str: ByteArray = format!(
//             "ParkingLot ({}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
//             *self.lot_id,
//             *self.name,
//             *self.location,
//             *self.coordinates,
//             *self.slot_count,
//             *self.hourly_rate_usd_cents,
//             *self.creator,
//             *self.wallet_address,
//             *self.is_active,
//             *self.registration_time
//         );
//         f.buffer.append(@str);
//         Result::Ok(())
//     }
// }

fn deploy_contract() -> ContractAddress {
    let contract = declare("Parking").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(
            @array![
                default_owner().into(), pragma_contract().into(), default_payment_token().into()
            ]
        )
        .expect('Deploy failed');
    contract_address
}

#[test]
fn test_contructor() {
    let contract_address = deploy_contract();
    let dispatcher = IParkingDispatcher { contract_address };
    let payment_token = dispatcher.get_payment_token();
    assert(payment_token == default_payment_token().into(), 'Invalid payment token');
}

#[test]
#[ignore]
fn test_get_available_parking_lot() {
    let contract_address = deploy_contract();
    let dispatcher = IParkingDispatcher { contract_address };

    dispatcher
        .register_parking_lot(
            1000,
            0x54657374205061726b696e67204e616d65,
            0x54657374205061726b696e67204e616d65,
            0x31332e3731383432343335313130332c203130302e35363338303731333839,
            2,
            200,
            default_wallet_address().into()
        );

    let after_register = dispatcher.get_available_slots(1000);
    assert(after_register.into() == 2, 'invalid available slot');
}

#[test]
#[fork("KATANA")]
fn test_using_forked_state() {
    // instantiate the dispatcher
    let dispatcher = IParkingDispatcher { contract_address: CONTRACT_ADDRESS.try_into().unwrap() };

    dispatcher
        .register_parking_lot(
            1001,
            0x54657374205061726b696e67204e616d65,
            0x54657374205061726b696e67204e616d65,
            0x31332e3731383432343335313130332c203130302e35363338303731333839,
            3,
            250,
            default_wallet_address().into()
        );

    let after_register = dispatcher.get_available_slots(1001);
    assert(after_register.into() == 3, 'invalid available slot');

    assert_eq!(after_register, 3);

    let info = dispatcher.get_parking_lot(1000);
    println!("{:?}", info);
    // let info_clone = info.clone();
    assert!(info.lot_id == 1000, "Not equal");
    // assert_eq!(info.clone().lot_id, 1000);
// assert_eq!(info.Serde, );
}
