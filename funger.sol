// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "./Swaper.sol";


interface Swaper {
    function swapInTokenToOutToken(uint256 amountIn, address _in, address _out) external returns (uint256 amountOut);
    function balanceForToken(address _tokenAddress) external view returns (uint256);
    function transferToken(address recipient, uint256 amount, address _tokenAddress) external returns(bool);
    function transferEth(address _to, uint256 _amount) external;
}

contract PolyToken is ERC20Capped, Ownable{

    uint public sentValue;
    uint public immutable _decimals = 0;
    uint public minimumContribution; // This is also the token price (goal_ / cap_)
    address public admin;
    uint public deadline; // Timestamp
    uint public goal;
    address public immutable wethContract = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    mapping(address => uint) public contributors;
    uint public noOfContributors;
    uint public raisedAmount;
    struct Request{
        string description;
        address payable swapContract;
        uint value;
        address inToken;
        address outToken;
        bool completed;
        uint noOfVoters;
        mapping(address => bool) voters;
    }

    mapping(uint => Request) public requests;

    uint public numRequests;

    constructor(
        string memory name_, 
        string memory symbol_, 
        uint256 cap_, // Max Supply
        uint goal_ // Amount in eth
        // uint deadline_ // Time in seconds after which no more tokens can be bought
        ) 
        ERC20(name_, symbol_) ERC20Capped(cap_){
            minimumContribution = goal_/cap_;
            goal = goal_; // Could be replaced for max supply
            // deadline = block.timestamp + deadline_;
            // minimumContribution = _minimumContribution; // This could be the price of the unit of the token
            admin = msg.sender;
    }
///////////////////////////////////////////////////////////////////////////////////////////
    // Holders of the the minted token can run the function
    modifier onlyHolder() {
        require (balanceOf(msg.sender) > 0, "You must be a contributor to vote!");
        _;
    }

    // Holders or Owner can run the function
    modifier ownerOrHolder() {
        require(balanceOf(msg.sender) > 0 || msg.sender == owner());
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin);
        _;
    }
//////////////////////////////////////////////////////////////////////////////////////////////
    // Events
    event ContributeEvent(address _sender, uint _value);
    event CreateRequestEvent(string _description, address _recipient, uint _value, address _inToken, address _outToken);
    event MakePaymentEvent(address _recipient, uint _value);
//////////////////////////////////////////////////////////////////////////////////////////////
    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    receive() external payable{
        issueToken();
    }

    // Calling functions from Swaper
    // function swapInTokenToOutToken(uint256 amountIn, address _in, address _out) external returns (uint256 amountOut);
    // function balanceForToken(address _tokenAddress) external view returns (uint256);
    // function transferToken(address recipient, uint256 amount, address _tokenAddress) external returns(bool);

    function swap(address _swaperAddr, uint256 _amount, address _in, address _out) public payable {
        // Swaper(_swaperAddr).swapInTokenToOutToken{value: _amount}(_amount, _in, _out);
        Swaper(_swaperAddr).swapInTokenToOutToken(_amount, _in, _out);
    }

    function swaperBalanceForToken(address _swaperAddr, address _tokenAddr) public view returns(uint256) {
        return (Swaper(_swaperAddr).balanceForToken(_tokenAddr));
    }

    function swapTransferToken(address _swaperAddr, address _recipient, uint256 _amount, address _tokenAddress) public payable {
        Swaper(_swaperAddr).transferToken(_recipient,_amount, _tokenAddress);
    }

    function swapTransferEth(address _swaperAddr, address payable _to, uint256 _amount) public payable {
        Swaper(_swaperAddr).transferEth(_to, _amount);
    }

//////////////////////////////////////////////////////////////////////////////////
    // Functions from DAO
    function getBalance() public view returns(uint){
        return address(this).balance;
    }

    function createRequest(string memory _description, address payable _swapContract, address _inToken, address _outToken, uint _value) public ownerOrHolder{
        Request storage newRequest = requests[numRequests];
        numRequests++;

        newRequest.description = _description;
        newRequest.swapContract = _swapContract;
        newRequest.value = _value;
        newRequest.inToken = _inToken;
        newRequest.outToken = _outToken;
        newRequest.completed = false;
        newRequest.noOfVoters = 0;

        emit CreateRequestEvent(_description, _swapContract, _value, _inToken, _outToken);
    }

    function voteRequest(uint _requestNo) public onlyHolder{
        Request storage thisRequest = requests[_requestNo];
        require(thisRequest.value > 0, "This request has not been created");
        require(thisRequest.completed == false, "The request is closed");
        require(thisRequest.voters[msg.sender] == false, "You have already voted!");
        thisRequest.voters[msg.sender] = true;
        thisRequest.noOfVoters++;
    }

    function cancelRequest(uint _requestNo) public onlyAdmin {
        Request storage thisRequest = requests[_requestNo];
        require(thisRequest.completed == false, "The request is closed");
        thisRequest.completed = true;
    } 

    function makePayment(uint _requestNo) public onlyAdmin{
        require(raisedAmount >= goal, "The contract has not raised the goal amount");
        Request storage thisRequest = requests[_requestNo];
        require(thisRequest.completed == false, "The request has been completed!");
        require(thisRequest.noOfVoters > noOfContributors / 2, "More than 50% of approvals required"); // 50% voted for this request

        // First we send eth to the Swaper contract
        transferEth(thisRequest.swapContract, thisRequest.value);
        // thisRequest.swapContract.transfer(thisRequest.value);

        // Second we tell Swaper to wrap teh eth that was just sent
        swapTransferEth(thisRequest.swapContract, payable(wethContract), thisRequest.value);

        // Third, we convert the weth to the desired ERC20
        swap(thisRequest.swapContract, thisRequest.value, thisRequest.inToken, thisRequest.outToken);

        // We update the status of teh request
        thisRequest.completed = true;
        emit MakePaymentEvent(thisRequest.swapContract, thisRequest.value);

        // swapTransfer(address _swaperAddr, address _recipient, uint256 _amount, address _tokenAddress);

        // swap(address _swaperAddr, uint256 _amount, address _in, address _out);
    }

    // Tokens will be minted and transfered to the account that deposits eth
    function issueToken() public payable {
        // require(block.timestamp < deadline, "Deadline has passed");

        // Making sure that the sent amount is a multiple of the price of the unit
        // token (minimumContribution)
        require(msg.value % minimumContribution == 0, 
        "Incorrect sent amount, the transfer must be exactly the price of the token unit (minimumContribution) or a multiple"
        );

        // How many tokens are being minted with the transfered amount?
        uint tokens = msg.value / minimumContribution;

        // Setting decimals (0 by default)
        _mint(msg.sender, tokens * 10 ** _decimals);

        if(contributors[msg.sender] == 0){
            noOfContributors++;
        }

        contributors[msg.sender] += msg.value;
        raisedAmount += msg.value;

        emit ContributeEvent(msg.sender, msg.value);
    }

    function transferEth(address payable _to, uint256 _amount) public payable {
        (bool sent, bytes memory data) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    // Token management
    function balanceForToken(address _tokenAddress) external view returns (uint256){
        IERC20 _inToken = IERC20(_tokenAddress);
        return(_inToken.balanceOf(address(this)));
    }

    function transferToken(address recipient, uint256 amount, address _tokenAddress) external returns(bool){
        IERC20 _inToken = IERC20(_tokenAddress);
        
        return(_inToken.transfer(recipient, amount));
    }

}
