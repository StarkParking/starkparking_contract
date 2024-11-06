use starknet::{ContractAddress, contract_address_const};

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

use starkparking_contract::parking::{
    IParkingDispatcher,
    IParkingDispatcherTrait, // IParkingSafeDispatcher, IParkingSafeDispatcherTrait
};

fn _default_owner() -> ContractAddress {
    contract_address_const::<0xdeadbeefdeadbeef>()
}

fn default_wallet_address() -> ContractAddress {
    contract_address_const::<0xa4e2d14481b49ce6376e3ca8412df5214225750ecd9e7c9f887904d436e811>()
}

fn default_payment_token() -> ContractAddress {
    contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>()
}

fn deploy_contract() -> ContractAddress {
    let contract = declare("Parking").unwrap().contract_class();
    // let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    let (contract_address, _) = contract
        .deploy(@array![default_payment_token().into()])
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
