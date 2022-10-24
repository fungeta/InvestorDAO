// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface Wrapper {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function totalSupply() external view returns (uint);
    function approve(address guy, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}

contract Swaper {
    address public constant routerAddress =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter public immutable swapRouter = ISwapRouter(routerAddress);
    // address public constant DAI = 0x73967c6a0904aA032C103b4104747E88c566B1A2;
    // address public constant LINK = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address payable public constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000;

    constructor() {}

    fallback() external payable {}

    receive() external payable{}

    function swapInTokenToOutToken(uint256 amountIn, address _in, address _out) 
        external returns (uint256 amountOut)
    {
        IERC20 _inToken = IERC20(_in);
        _inToken.approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _in,
                tokenOut: _out,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function balanceForToken(address _tokenAddress) external view returns (uint256){
        IERC20 _inToken = IERC20(_tokenAddress);
        return(_inToken.balanceOf(address(this)));
    }

    function transferToken(address recipient, uint256 amount, address _tokenAddress) external returns(bool){
        IERC20 _inToken = IERC20(_tokenAddress);
        
        return(_inToken.transfer(recipient, amount));
    }

    function transferEth(address payable _to, uint256 _amount) public payable {
        (bool sent, bytes memory data) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    // WRAPPER
    // function wrapEth(address payable _wrapper) public payable {
    //     Wrapper(_wrapper).deposit();
    // }

    function unwrapEth(address payable _wrapper, uint256 _amount) public payable {
        _wrapper = WETH;
        Wrapper(_wrapper).withdraw(_amount);
    }

}   
