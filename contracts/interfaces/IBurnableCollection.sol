pragma ton-solidity >=0.57.1;

interface IBurnableCollection {

    function acceptNftBurn(
        uint256 _id,
        address _owner,
        address _manager,
        address _sendGasTo,
        address _callbackTo,
        TvmCell _callbackPayload
    ) external;

}