use starknet::ContractAddress;

#[starknet::interface]
pub trait IMetaverseAucion<TContractState> {
    fn bid(ref self: TContractState, item_id: u256, amount: u256);
    fn list_item(ref self: TContractState, item_id: u256);
    fn accept_highest_bid(ref self: TContractState, item_id: u256);
}

#[starknet::contract]
mod MetaverseAucion {
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{get_caller_address, get_contract_address, ContractAddress, get_block_timestamp};
    use starknet::storage::Map;
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess,
        StoragePointerReadAccess, StoragePointerWriteAccess
    };
    #[feature("deprecated-list-trait")]
    use alexandria_storage::list::{ListTrait, List};
    use core::num::traits::Zero;

    // Definition of the Bid struct
    // PartialEq is used to compare the struct
    // Serde is used to serialize and deserialize the struct
    // starknet::Store is used to store the struct in the contract storage
    #[derive(PartialEq, Drop, Serde, Copy, starknet::Store, Hash)]
    struct Bid {
        block_timestamp: u64,
        bidder: ContractAddress,
        item_id: u256,
        amount: u256,
    }

    #[storage]
    struct Storage {
        nft: IERC721Dispatcher, // The NFT contract
        eth: IERC20Dispatcher, // The ETH contract
        listed_items: Map<u256, ContractAddress>, // The items in the auction, item_id -> owner
        item_bids: Map<u256, List<Bid>>, // Maps between item id to it's bids
    }

    #[constructor]
    fn constructor(ref self: ContractState, eth: ContractAddress, nft: ContractAddress) {
        self.nft.write(IERC721Dispatcher { contract_address: nft });
        self.eth.write(IERC20Dispatcher { contract_address: eth });
    }

    #[abi(embed_v0)]
    impl MetaverseAucionImpl of super::IMetaverseAucion<ContractState> {

        // Bid on an existing item
        // @param item_id: The id of the item
        // @param amount: The amount to bid
        fn bid(ref self: ContractState, item_id: u256, amount: u256) {
            let mut item_bids = self.item_bids.read(item_id);

            // If it's not the first bid
            if (item_bids.len() != 0) {
                let last_bid: Bid = item_bids[item_bids.len() - 1];

                // Make sure that this bid is higher than the previous bid (if there is one)
                assert(last_bid.amount < amount, 'Bid not high enough');
            }

            // Create a new bid and write the data to the storage
            let caller = get_caller_address();
            let new_bid = Bid { 
                bidder: caller, 
                item_id: item_id, 
                amount: amount, 
                block_timestamp: get_block_timestamp() 
            };

            // Update the state
            assert(item_bids.append(new_bid).is_ok(), 'Bid append failed');

            // Transfer the bidded amount to the contract
            self.eth.read().transfer_from(caller, get_contract_address(), amount);
        }

        // List an item for sale
        // @param item_id: The id of the item
        fn list_item(ref self: ContractState, item_id: u256) {
            // Make sure that the item wasn't listed before
            assert(self.listed_items.read(item_id).is_zero(), 'Item already listed');
            let caller = get_caller_address();
            self.listed_items.write(item_id, caller);
            self.nft.read().transfer_from(caller, get_contract_address(), item_id);
        }

        // Accept the current highest bid
        // @param item_id: The id of the item we want to accept the bid for
        fn accept_highest_bid(ref self: ContractState, item_id: u256) {
            let item_owner = self.listed_items.read(item_id);
            let mut item_bids = self.item_bids.read(item_id);
            assert(item_bids.len() > 0, 'No bids');
            let highest_bid = self._get_highest_bid(@item_bids);

            // Only the owner of the listed item can accept the bid
            assert(item_owner == get_caller_address(), 'Not the owner');

            // Refund the loosing bids
            let mut i = 0;
            while i < item_bids.len() - 1 {
                let mut current_bid = item_bids[i];
                self.eth.read().transfer(current_bid.bidder, current_bid.amount);

                // Reset bid
                current_bid.amount = 0.try_into().unwrap();
                current_bid.item_id = 0.try_into().unwrap();
                current_bid.bidder = 0.try_into().unwrap();
                current_bid.block_timestamp = 0.try_into().unwrap();
                assert(item_bids.set(i, current_bid).is_ok(), 'bid reset failed');

                i += 1;
            };

            // Transfer the item to the highest bidder
            self.nft.read().transfer_from(get_contract_address(), highest_bid.bidder, item_id);
            // Transfer the payment amount to the owner
            self.eth.read().transfer(item_owner, highest_bid.amount);

            // Delist the item
            self.listed_items.write(item_id, 0.try_into().unwrap());
            self._clean_bids(ref item_bids);
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn _get_highest_bid(self: @ContractState, item_bids: @List<Bid>) -> Bid {
            assert(item_bids.len() > 0, 'No bids');
            return item_bids[item_bids.len() - 1];
        }

        fn _clean_bids(self: @ContractState, ref item_bids: List<Bid>) {
            item_bids.clean();
        }
    }
}
