pragma ever-solidity >= 0.61.2;

import "../structures/IMarketFeeStructure.sol";

interface IEventsMarketFeeOffer is IMarketFeeStructure {
    event MarketFeeChanged(address auction, MarketFee fee);
    event MarketFeeWithheld(uint128 amount, address tokenRoot);
}