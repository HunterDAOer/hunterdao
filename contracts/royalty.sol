// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external pure returns (address);

    function factory() external pure returns (address);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract Royalty is Ownable {
    using SafeMath for uint256;
    // Dead address to burn tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    // address of hunter token
    address public hunter;
    // address of hunter owner
    address public hunterOwner;
    // address of hunterA token
    address public hunterA;
    // address of exchange router
    address public router;
    // NFT royalties Token
    address[] public feeToken;
    // fee token isExists
    mapping(address => bool) public feeTokenIsExists;
    // array path of token and hunter
    mapping(address => address[]) public swapPath;
    // Commission fee ratio
    uint256 public tax;

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyHunterOwner() {
        require(hunterOwner == _msgSender(), "caller is not the hunter owner");
        _;
    }

    constructor(
        address _hunter,
        address _hunterOwner,
        address _hunterA,
        address _router,
        uint256 _tax
    ) {
        require(_hunterOwner != address(0),"initialize: Invalid address");
        require(_hunterA != address(0),"initialize: Invalid address");
        require(_router != address(0),"initialize: Invalid address");
        require(_router != address(0), "initialize: Invalid address");
        require(tax >= 0 && tax < 100, "initialize: Invalid address");

        hunter = _hunter;
        hunterOwner = _hunterOwner;
        hunterA = _hunterA;
        router = _router;
        tax = _tax;
    }

    // Fee currency is other, new transaction currency
    function setSwapPath(address _feeToken, address[] memory _swapPath) public onlyOwner {
        require(_swapPath[_swapPath.length - 1] == hunter && _swapPath[0] == _feeToken, "Wrong trading path");
        if(!feeTokenIsExists[_feeToken]){
            feeToken.push(_feeToken);
            feeTokenIsExists[_feeToken] = true;
        }
        swapPath[_feeToken] = _swapPath;
        emit SetSwapPath(_feeToken);
    }


    // Fee currency is other, new transaction currency
    function setHunterA(address _hunterA) public onlyHunterOwner {
        hunterA = _hunterA;
        emit SetHunterA(hunterA);
    }

    // Capital allocation, Side Indicates the current recommended value 115
    function distribution(address _token, uint256 _side) public onlyOwner {
        require(swapPath[_token].length > 0, "Wrong trading path");
        require(_side > 0 && _side < 500, "Wrong side");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "No income");

        // Transferred to the owner
        IERC20(_token).transfer(owner(), balance.mul(100 - tax).div(100));

        uint256 hunterFee = balance.mul(tax).div(100);
        // Current exchange quantity
        uint256[] memory hunterAmount = IUniswapV2Router(router).getAmountsOut(hunterFee, swapPath[_token]);
        // Minimum quantity received
        uint256 side = uint256(1000).mul(1000000).div(1000+_side);
        uint256 hunterSideAmount = hunterAmount[hunterAmount.length - 1].mul(side).div(1000000);
        
        // approve
        IERC20(_token).approve(router, hunterFee);
        // swap
        IUniswapV2Router(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            hunterFee,
            hunterSideAmount,
            swapPath[_token],
            address(this),
            block.timestamp
        );

        uint256 hunterBalance = IERC20(hunter).balanceOf(address(this));
        IERC20(hunter).transfer(DEAD_ADDRESS, hunterBalance.div(2));
        IERC20(hunter).transfer(hunterA, hunterBalance.div(2));
    }

    // weth into eth
    function toWeth(uint256 amount) public onlyOwner {
        IWETH(IUniswapV2Router(router).WETH()).deposit{value: amount}();
    }
    
    receive() external payable {}

    event SetSwapPath(address);
    event SetHunterA(address);
}

