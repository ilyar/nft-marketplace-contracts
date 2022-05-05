pragma ton-solidity >=0.57.1;
pragma AbiHeader expire;
pragma AbiHeader pubkey;
pragma AbiHeader time;

import './libraries/Gas.sol';
import './errors/AuctionErrors.sol';

import './abstract/OffersRoot.sol';

import './Nft.sol';
import './modules/TIP4_1/interfaces/INftChangeManager.sol';
import './modules/TIP4_1/interfaces/ITIP4_1NFT.sol';
import './AuctionTip3.sol';

contract AuctionRootTip3 is OffersRoot, INftChangeManager {

    uint64 static nonce_;

    struct MarketOffer {
        address collection;
        address nftOwner;
        address nft;
        address offer;
        uint128 price;
        uint128 auctionDuration;
        uint64 deployNonce;
    }

    uint8 public auctionBidDelta;
    uint8 public auctionBidDeltaDecimals;

    event AuctionDeployed(address offerAddress, MarketOffer offerInfo);
    event AuctionDeclined(address nftOwner, address dataAddress);

    constructor(
        TvmCell _codeNft,
        address _owner,
        TvmCell _offerCode,
        uint128 _deploymentFee,
        uint8 _marketFee, 
        uint8 _marketFeeDecimals,
        uint8 _auctionBidDelta,
        uint8 _auctionBidDeltaDecimals,
        address _sendGasTo
    ) OwnableInternal(
        _owner
    )
        public 
    {
        tvm.accept();
        tvm.rawReserve(Gas.AUCTION_ROOT_INITIAL_BALANCE, 0);
        // Method and properties are declared in OffersRoot
        setDefaultProperties(
            _codeNft,
            _owner,
            _offerCode,
            _deploymentFee,
            _marketFee, 
            _marketFeeDecimals
        );

        auctionBidDelta = _auctionBidDelta;
        auctionBidDeltaDecimals = _auctionBidDeltaDecimals;
        _sendGasTo.transfer({ value: 0, flag: 128, bounce: false });
    }

    function onNftChangeManager(
        uint256 id,
        address nftOwner,
        address oldManager,
        address newManager,
        address collection,
        address sendGasTo,
        TvmCell payload
    ) external override {
        require(newManager == address(this));
        tvm.rawReserve(Gas.AUCTION_ROOT_INITIAL_BALANCE, 0);
        address expectedSender = _resolveNft(collection, id);
        bool isDeclined = false;
        if (expectedSender == msg.sender && nftOwner == owner() && payload.toSlice().bits() == 523) {
            (
                address _paymentTokenRoot,
                uint128 _price,
                uint64 _auctionStartTime,
                uint64 _auctionDuration
            ) = payload.toSlice().decode(address, uint128, uint64, uint64);
            if (
                _paymentTokenRoot.value > 0 &&
                _price >= 0 &&
                _auctionStartTime > 0 &&
                _auctionDuration > 0 
            ) {
                address offerAddress = new AuctionTip3 {
                    wid: address(this).wid,
                    value: Gas.DEPLOY_AUCTION_VALUE,
                    flag: 1,
                    code: offerCode,
                    varInit: {
                        price: _price,
                        nft: msg.sender,
                        nonce_: tx.timestamp
                    }
                }(
                    address(this),
                    collection,
                    nftOwner,
                    deploymentFeePart * 2, 
                    marketFee, 
                    marketFeeDecimals,
                    _auctionStartTime, 
                    _auctionDuration,
                    auctionBidDelta,
                    _paymentTokenRoot,
                    nftOwner
                );
                MarketOffer offerInfo = MarketOffer(collection, nftOwner, msg.sender, offerAddress, _price, _auctionDuration, tx.timestamp);
                emit AuctionDeployed(offerAddress, offerInfo);
                mapping(address => ITIP4_1NFT.CallbackParams) callbacks;
                ITIP4_1NFT(msg.sender).changeManager{value: 0, flag: 128}(
                    offerAddress,
                    sendGasTo,
                    callbacks
                );
            } else {
                isDeclined = true;
            }
        } else {
            isDeclined = true;
        }
        
        if (isDeclined) {
            emit AuctionDeclined(nftOwner, msg.sender);
            TvmCell empty;
            mapping(address => ITIP4_1NFT.CallbackParams) callbacks;
            ITIP4_1NFT(msg.sender).changeManager{value: 0, flag: 128}(
                nftOwner,
                sendGasTo,
                callbacks
            );
        }
    }

    function getOfferAddress(
        address _nft,
        uint128 _price,
        uint64 _nonce
    ) 
        public 
        view 
        returns (address offerAddress)
    {
        TvmCell data = tvm.buildStateInit({
            contr: AuctionTip3,
            code: offerCode,
            varInit: {
                price: _price,
                nft: _nft,
                nonce_: _nonce
            }
        });

        offerAddress = address(tvm.hash(data));
    }

    function buildAuctionCreationPayload (
        address _paymentTokenRoot,
        uint128 _price,
        uint64 _auctionStartTime,
        uint64 _auctionDuration
    ) external pure responsible returns(TvmCell) {
        TvmBuilder builder;
        builder.store(_paymentTokenRoot, _price, _auctionStartTime, _auctionDuration);
        return builder.toCell();
    }

    function _resolveNft(
        address collection,
        uint256 id
    ) internal virtual view returns (address nft) {
        TvmCell code = _buildNftCode(collection);
        TvmCell state = _buildNftState(code, id);
        uint256 hashState = tvm.hash(state);
        nft = address.makeAddrStd(address(this).wid, hashState);
    }
   function _buildNftCode(address collection) internal virtual view returns (TvmCell) {
        TvmBuilder salt;
        salt.store(collection);
        return tvm.setCodeSalt(codeNft, salt.toCell());
    }
    function _buildNftState(
        TvmCell code,
        uint256 id
    ) internal virtual pure returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TIP4_1Nft,
            varInit: {_id: id},
            code: code
        });
    }
}