pragma solidity >=0.6.0;

import "../client/node_modules/@chainlink/contracts/src/v0.6/interfaces/LinkTokenInterface.sol";

import "./Scratch.sol";

interface ERC20Interface {

    /// @param _owner The address from which the balance will be retrieved
    /// @return balance the balance
    function balanceOf(address _owner) external view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transfer(address _to, uint256 _value)  external returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return success Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return success Whether the approval was successful or not
    function approve(address _spender  , uint256 _value) external returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return remaining Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract ScratchToken is ERC20Interface {
    uint256 constant private MAX_UINT256 = 2**256 - 1;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowed;
    uint256 public totalSupply;
    
    address public tokenSale;

    address public scratch;

    LinkTokenInterface private LINK;

    /*
    NOTE:
    The following variables are OPTIONAL vanities. One does not have to include them.
    They allow one to customise the token contract & in no way influences the core functionality. 
    Some wallets/interfaces might not even bother to look at this information.
    */
    string public name;                   //fancy name: eg Simon Bucks
    uint8 public decimals;                //How many decimals to show.
    string public symbol;                 //An identifier: eg SBX

    constructor(string memory _tokenName, uint8 _decimalUnits, string  memory _tokenSymbol) public{
        //balances[msg.sender] = _initialAmount;             // Give the creator all initial tokens
        totalSupply = 250000 * 10 ** 18;                      // Update total supply
        name = _tokenName;                                   // Set the name for display purposes
        decimals = _decimalUnits;                            // Amount of decimals for display purposes
        symbol = _tokenSymbol;                               // Set the symbol for display purposes

        tokenSale = address(new ScratchTokenSale());

        balances[tokenSale] = 237500 * 10 ** 18;

        balances[msg.sender] = 12500 * 10 ** 18;

        LINK = LinkTokenInterface(0xa36085F69e2889c224210F603D836748e7dC0088);
        
        //owner = msg.sender;
    }

    // function called by Scratch main contract to mint amount tokens
    function mint(address receiver, uint amount) public {
        require(msg.sender == scratch, "Invalid mint attempt");
        totalSupply += amount;
        balances[receiver] += amount;
    }

    function getTotalSupply() public view returns(uint supply){
        return totalSupply;
    }

    function endSale() public {
        require(ScratchTokenSale(tokenSale).saleOver() && address(scratch) == address(0), "The token sale is not over yet.");
        scratch = address(new Scratch(LINK.balanceOf(address(this)), this));
        LINK.transfer(scratch, LINK.balanceOf(address(this)));
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        require(balances[msg.sender] >= _value, "token balance is lower than the value requested");
        require(Scratch(scratch).getPlayerRound(_to) == Scratch(scratch).getRound(), "The players round must be current round.");
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value); //solhint-disable-line indent, no-unused-vars
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        uint256 allowance = allowed[_from][msg.sender];
        require(balances[_from] >= _value && allowance >= _value, "token balance or allowance is lower than amount requested");
        require(Scratch(scratch).getPlayerRound(_to) == Scratch(scratch).getRound(), "The players round must be current round.");
        balances[_to] += _value;
        balances[_from] -= _value;
        if (allowance < MAX_UINT256) {
            allowed[_from][msg.sender] -= _value;
        }
        emit Transfer(_from, _to, _value); //solhint-disable-line indent, no-unused-vars
        return true;
    }

    function balanceOf(address _owner) public override view returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value); //solhint-disable-line indent, no-unused-vars
        return true;
    }

    function allowance(address _owner, address _spender) public override view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
}

// Contract to distribute ScratchTokens to the initial Scratch prize pool providers.
contract ScratchTokenSale{

    // Variable to hold the address of the ScratchToken.
    address scratchToken;

    uint saleTotalTokens;

    mapping(address => bool) public poolProviders;

    mapping(address => uint) linkProvided;

    mapping(address => bool) claimed;

    LinkTokenInterface private LINK;
    // 0xa36085F69e2889c224210F603D836748e7dC0088 link kovan address

    // Block marking the end of the sale.
    uint endblock;

    event SuppliedPool(uint totalLink, uint provided);

    event ReceivedTokens(uint received);

    constructor() public{
        LINK = LinkTokenInterface(0xa36085F69e2889c224210F603D836748e7dC0088);
        scratchToken = msg.sender;
        endblock = block.number + 100; //19200; // about three days worth of time to donate to the contract
        saleTotalTokens = 237500;

        poolProviders[0x60A750f8f101e8BCE54852849105d2Ced89f1a18] = true;
    }

    // Function to be called by initial prize pool providers to provide link.
    function supplyPrizePool() public{
        require(!saleOver() , "The sale is over.");
        require(poolProviders[msg.sender] == true, "You are not part of the scratch donator pool");
        uint providerAllowance = LINK.allowance(msg.sender, address(this));
        require(providerAllowance > 10 ** 18, "Must provide more then one link");
        LINK.transferFrom(msg.sender, scratchToken, providerAllowance);
        linkProvided[msg.sender] += providerAllowance;
        emit SuppliedPool(LINK.balanceOf(address(scratchToken)), linkProvided[msg.sender]);
    }

    function recieveTokens() public{
        require(saleOver(), "The sale is not over yet.");
        require(claimed[msg.sender] == false, "Tokens already claimed by this address");
        claimed[msg.sender] == true;
        uint receivedTokens = (linkProvided[msg.sender] /(LINK.balanceOf(address(scratchToken)) / 10 ** 18)) * saleTotalTokens;
        ScratchToken(scratchToken).transfer(msg.sender, receivedTokens);
        emit ReceivedTokens(receivedTokens);
    }

    function saleOver() public view returns(bool over){
        return block.number > endblock;
    }

}

