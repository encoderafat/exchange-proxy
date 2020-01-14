// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.5.12;
pragma experimental ABIEncoderV2;


// DO NOT USE ON MAINNET
// This contract is under development and tokens can easily get stuck forever

contract PoolInterface {
    function swapExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
    function swapExactAmountOut(address, uint, address, uint, uint) external returns (uint, uint);
}

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public returns (bool);
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract ExchangeProxy {

    struct Swap {
        address pool;
        uint    tokenInParam; // tokenInAmount / maxAmountIn / limitAmountIn
        uint    tokenOutParam; // minAmountOut / tokenAmountOut / limitAmountOut
        uint    maxPrice;
    }

    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    bool private _mutex;

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    // TODO - consider if function should revert if not all trades execute
    function batchSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )   
        public
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.transferFrom(msg.sender, address(this), totalAmountIn);
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        TO.transfer(msg.sender, totalAmountOut);
        return totalAmountOut;
    }

    // TODO - consider if function should revert if not all trades execute
    function batchSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountOut,
        uint maxTotalAmountIn
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.transferFrom(msg.sender, address(this), maxTotalAmountIn);
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");
        TO.transfer(msg.sender, totalAmountOut);
        TI.transfer(msg.sender, TI.balanceOf(address(this)));
        return totalAmountIn;
    }

    function batchEthInSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )
        public payable
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.deposit.value(msg.value)();
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        TO.transfer(msg.sender, totalAmountOut);
        return totalAmountOut;
    }

    function batchEthOutSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        TO.withdraw(totalAmountOut);
        (bool xfer,) = msg.sender.call.value(totalAmountOut)("");
        require(xfer, "ERR_ETH_FAILED");
        return totalAmountOut;
    }

    function batchEthInSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountOut,
        uint maxTotalAmountIn
    )
        public payable
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.deposit.value(msg.value)();
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");
        TO.transfer(msg.sender, totalAmountOut);
        uint wethBalance = TI.balanceOf(address(this));
        TI.withdraw(wethBalance);
        (bool xfer,) = msg.sender.call.value(wethBalance)("");
        require(xfer, "ERR_ETH_FAILED");
        return totalAmountIn;
    }

    function batchEthOutSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountOut,
        uint maxTotalAmountIn
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.transferFrom(msg.sender, address(this), maxTotalAmountIn);
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");
        TI.transfer(msg.sender, TI.balanceOf(address(this)));
        TO.withdraw(totalAmountOut);
        (bool xfer,) = msg.sender.call.value(totalAmountOut)("");
        require(xfer, "ERR_ETH_FAILED");
        return totalAmountIn;
    }
}