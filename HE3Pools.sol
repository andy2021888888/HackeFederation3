// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.2/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.2/contracts/utils/structs/EnumerableSet.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.2/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.2/contracts/access/Ownable.sol";
import "./HE3.sol";

contract HE3Pools is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 initDebt; // init debt when user first deposit
        bool    isAirDrop; // is airdrop
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20  lpToken; // Address of LP token contract.
        uint256 totalLp; // total token of lpToken.
        uint256 allocPoint; // How many allocation points assigned to this pool. he3s to distribute per block.
        uint256 lastRewardSecond; // Last block number that he3s distribution occurs.
        uint256 accHe3PerShare; // Accumulated he3s per share, times 1e12. See below.
        uint256 totalHE3Mint; // the total number of he3 mint.
        uint256 timestamp; // the time of the pool created.
        bool isStart; // is start mining.
    }
    // The HE3 TOKEN!
    HE3Token public he3;
    // HE3 tokens created per Second, needs to div 1e18.
    uint256 public he3PerSecond;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // airdrop end block;
    uint256 public airdropEndBlock;
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 income);
    event Airdrop(address[] dests, uint256[] values);

    constructor(
        HE3Token _he3,
        uint256 _he3PerSecond,
        uint256 _airdropEndBlock
    ) {
        he3 = _he3;
        he3PerSecond = _he3PerSecond;
        airdropEndBlock = block.number.add(_airdropEndBlock);
    }
    
    function upHE3PerSecond(uint256 _he3PerSecond) public onlyOwner {
        he3PerSecond = _he3PerSecond;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                totalLp: 0,
                allocPoint: _allocPoint,
                lastRewardSecond: block.timestamp,
                accHe3PerShare: 0,
                totalHE3Mint: 0,
                timestamp: 0,
                isStart: false
            })
        );
    }

    // Update the given pool's HE3 allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // View function to see pending HE3s on frontend.
    function pendingHe3(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHe3PerShare = pool.accHe3PerShare;
        //uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 lpSupply = pool.totalLp;
        if (block.timestamp > pool.lastRewardSecond && lpSupply != 0) {
            uint256 multiplier = 
                block.timestamp.sub(pool.lastRewardSecond);
            uint256 he3Reward =
                multiplier.mul(he3PerSecond).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accHe3PerShare = accHe3PerShare.add(
                he3Reward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accHe3PerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardSecond) {
            return;
        }
        //uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 lpSupply = pool.totalLp;
        if (lpSupply == 0) {
            pool.lastRewardSecond = block.timestamp;
            return;
        }
        uint256 multiplier = 
                block.timestamp.sub(pool.lastRewardSecond);
        uint256 he3Reward =
            multiplier.mul(he3PerSecond).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        he3.mint(address(this), he3Reward);
        pool.totalHE3Mint = pool.totalHE3Mint.add(he3Reward);
        pool.accHe3PerShare = pool.accHe3PerShare.add(
            he3Reward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardSecond = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for HE3 allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = 0;
        if (user.amount > 0) {
            pending =
                user.amount.mul(pool.accHe3PerShare).div(1e12).sub(
                    user.rewardDebt
                );
        //    safeHe3Transfer(msg.sender, pending);
        }
        if (pool.isStart == false) {
            pool.timestamp = block.timestamp;
            pool.isStart = true;
        }
        
        user.initDebt = user.initDebt.add(_amount.mul(pool.accHe3PerShare).div(1e12));
        
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accHe3PerShare).div(1e12).sub(pending);
        pool.totalLp = pool.totalLp.add(_amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accHe3PerShare).div(1e12).sub(
                user.rewardDebt
            );
        require(_amount <= pending, "_amount error.");
        safeHe3Transfer(msg.sender, _amount);
        //user.rewardDebt = user.amount.mul(pool.accHe3PerShare).div(1e12);
        user.rewardDebt = user.rewardDebt.add(_amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Safe he3 transfer function, just in case if rounding error causes pool to not have enough HE3s.
    function safeHe3Transfer(address _to, uint256 _amount) internal {
        uint256 he3Bal = he3.balanceOf(address(this));
        if (_amount > he3Bal) {
            he3.transfer(_to, he3Bal);
        } else {
            he3.transfer(_to, _amount);
        }
    }
    
    // Airdrop for user from ethereum
    function airdrop(address[] memory dests, uint256[] memory values) onlyOwner public returns (uint256) {
        uint256 i = 0;
        require(block.number < airdropEndBlock, "bad time.");
        updatePool(0);
        PoolInfo storage pool = poolInfo[0];
        while (i < dests.length) {
            UserInfo storage user = userInfo[0][dests[i]];
            if (user.isAirDrop == false) {
                user.amount = user.amount.add(values[i]);
                user.initDebt = user.initDebt.add(values[i].mul(pool.accHe3PerShare).div(1e12));
                user.rewardDebt = user.rewardDebt.add(values[i].mul(pool.accHe3PerShare).div(1e12));
                user.isAirDrop = true;
                pool.totalLp = pool.totalLp.add(values[i]);
            }
            i += 1;
        }
        emit Airdrop(dests, values);
        return(i);
    }
}
