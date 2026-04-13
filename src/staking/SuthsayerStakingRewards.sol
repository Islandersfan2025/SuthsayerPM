// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ISuthsayerRewardToken is IERC20 {
    function mintRewards(address to, uint256 amount, bytes32 campaignId) external;
}

contract SuthsayerStakingRewards is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant ACC_REWARD_PRECISION = 1e24;

    struct PoolInfo {
        IERC20 stakingToken;
        uint96 allocPoint;
        uint32 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        bytes32 campaignId;
        bool exists;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    ISuthsayerRewardToken public immutable rewardToken;

    uint256 public rewardPerSecond;
    uint256 public startTime;
    uint256 public totalAllocPoint;

    PoolInfo[] public pools;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event PoolAdded(uint256 indexed pid, address indexed stakingToken, uint256 allocPoint, bytes32 indexed campaignId);
    event PoolUpdated(uint256 indexed pid, uint256 oldAllocPoint, uint256 newAllocPoint, bytes32 oldCampaignId, bytes32 newCampaignId);
    event RewardPerSecondUpdated(uint256 oldRewardPerSecond, uint256 newRewardPerSecond);
    event StartTimeUpdated(uint256 oldStartTime, uint256 newStartTime);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount, bytes32 indexed campaignId);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    error ZeroAddress();
    error InvalidPool();
    error PoolAlreadyExists();
    error InvalidStartTime();
    error AmountZero();
    error InsufficientBalance();

    constructor(
        address rewardToken_,
        address initialOwner_,
        uint256 rewardPerSecond_,
        uint256 startTime_
    ) Ownable(initialOwner_) {
        if (rewardToken_ == address(0) || initialOwner_ == address(0)) revert ZeroAddress();
        if (startTime_ < block.timestamp) revert InvalidStartTime();

        rewardToken = ISuthsayerRewardToken(rewardToken_);
        rewardPerSecond = rewardPerSecond_;
        startTime = startTime_;
    }

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function addPool(IERC20 stakingToken_, uint96 allocPoint_, bytes32 campaignId_, bool withUpdate) external onlyOwner {
        if (address(stakingToken_) == address(0)) revert ZeroAddress();
        if (_poolExists(stakingToken_)) revert PoolAlreadyExists();
        if (withUpdate) massUpdatePools();

        uint32 rewardStart = uint32(_rewardableTimestamp());
        totalAllocPoint += allocPoint_;
        pools.push(
            PoolInfo({
                stakingToken: stakingToken_,
                allocPoint: allocPoint_,
                lastRewardTime: rewardStart,
                accRewardPerShare: 0,
                totalStaked: 0,
                campaignId: campaignId_,
                exists: true
            })
        );

        emit PoolAdded(pools.length - 1, address(stakingToken_), allocPoint_, campaignId_);
    }

    function setPool(uint256 pid, uint96 newAllocPoint, bytes32 newCampaignId, bool withUpdate) external onlyOwner {
        PoolInfo storage pool = _getPool(pid);
        if (withUpdate) massUpdatePools();

        uint256 oldAllocPoint = pool.allocPoint;
        bytes32 oldCampaignId = pool.campaignId;
        totalAllocPoint = totalAllocPoint - oldAllocPoint + newAllocPoint;
        pool.allocPoint = newAllocPoint;
        pool.campaignId = newCampaignId;

        emit PoolUpdated(pid, oldAllocPoint, newAllocPoint, oldCampaignId, newCampaignId);
    }

    function setRewardPerSecond(uint256 newRewardPerSecond, bool withUpdate) external onlyOwner {
        if (withUpdate) massUpdatePools();
        emit RewardPerSecondUpdated(rewardPerSecond, newRewardPerSecond);
        rewardPerSecond = newRewardPerSecond;
    }

    function setStartTime(uint256 newStartTime, bool withUpdate) external onlyOwner {
        if (block.timestamp >= startTime) revert InvalidStartTime();
        if (newStartTime < block.timestamp) revert InvalidStartTime();
        if (withUpdate) massUpdatePools();

        emit StartTimeUpdated(startTime, newStartTime);
        startTime = newStartTime;

        uint32 rewardStart = uint32(_rewardableTimestamp());
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; ++i) {
            if (pools[i].totalStaked == 0) {
                pools[i].lastRewardTime = rewardStart;
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function massUpdatePools() public {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; ++i) {
            _updatePool(i);
        }
    }

    function updatePool(uint256 pid) external returns (PoolInfo memory pool) {
        pool = _updatePool(pid);
    }

    function pendingRewards(uint256 pid, address account) external view returns (uint256 pending) {
        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][account];

        uint256 accRewardPerShare_ = pool.accRewardPerShare;
        uint256 stakedSupply = pool.totalStaked;

        if (block.timestamp > pool.lastRewardTime && stakedSupply != 0 && totalAllocPoint != 0) {
            uint256 elapsed = _rewardableTimestamp() - pool.lastRewardTime;
            if (elapsed != 0) {
                uint256 poolReward = (elapsed * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
                accRewardPerShare_ += (poolReward * ACC_REWARD_PRECISION) / stakedSupply;
            }
        }

        pending = ((user.amount * accRewardPerShare_) / ACC_REWARD_PRECISION) - user.rewardDebt;
    }

    function deposit(uint256 pid, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert AmountZero();

        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        _updatePool(pid);
        _harvest(pid, msg.sender, pool, user);

        pool.stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        pool.totalStaked += amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION;

        emit Deposit(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external nonReentrant whenNotPaused {
        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        if (amount > user.amount) revert InsufficientBalance();

        _updatePool(pid);
        _harvest(pid, msg.sender, pool, user);

        if (amount != 0) {
            user.amount -= amount;
            pool.totalStaked -= amount;
            pool.stakingToken.safeTransfer(msg.sender, amount);
        }

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION;
        emit Withdraw(msg.sender, pid, amount);
    }

    function claim(uint256 pid) external nonReentrant whenNotPaused returns (uint256 claimed) {
        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        _updatePool(pid);
        claimed = _harvest(pid, msg.sender, pool, user);
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION;
    }

    function exit(uint256 pid) external nonReentrant whenNotPaused returns (uint256 withdrawn, uint256 claimed) {
        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        _updatePool(pid);
        claimed = _harvest(pid, msg.sender, pool, user);

        withdrawn = user.amount;
        if (withdrawn != 0) {
            user.amount = 0;
            pool.totalStaked -= withdrawn;
            pool.stakingToken.safeTransfer(msg.sender, withdrawn);
        }

        user.rewardDebt = 0;
        emit Withdraw(msg.sender, pid, withdrawn);
    }

    function emergencyWithdraw(uint256 pid) external nonReentrant {
        PoolInfo storage pool = _getPool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        pool.stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    function _harvest(uint256 pid, address to, PoolInfo storage pool, UserInfo storage user) internal returns (uint256 claimed) {
        uint256 accumulated = (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION;
        claimed = accumulated - user.rewardDebt;
        if (claimed != 0) {
            rewardToken.mintRewards(to, claimed, pool.campaignId);
            emit Claim(to, pid, claimed, pool.campaignId);
        }
    }

    function _updatePool(uint256 pid) internal returns (PoolInfo memory pool_) {
        PoolInfo storage pool = _getPool(pid);
        uint256 currentTimestamp = _rewardableTimestamp();

        if (currentTimestamp <= pool.lastRewardTime) {
            return pool;
        }

        uint256 stakedSupply = pool.totalStaked;
        if (stakedSupply == 0 || pool.allocPoint == 0 || totalAllocPoint == 0) {
            pool.lastRewardTime = uint32(currentTimestamp);
            return pool;
        }

        uint256 elapsed = currentTimestamp - pool.lastRewardTime;
        uint256 poolReward = (elapsed * rewardPerSecond * pool.allocPoint) / totalAllocPoint;
        pool.accRewardPerShare += (poolReward * ACC_REWARD_PRECISION) / stakedSupply;
        pool.lastRewardTime = uint32(currentTimestamp);

        return pool;
    }

    function _rewardableTimestamp() internal view returns (uint256) {
        return block.timestamp < startTime ? startTime : block.timestamp;
    }

    function _poolExists(IERC20 token) internal view returns (bool) {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; ++i) {
            if (address(pools[i].stakingToken) == address(token)) {
                return true;
            }
        }
        return false;
    }

    function _getPool(uint256 pid) internal view returns (PoolInfo storage pool) {
        if (pid >= pools.length) revert InvalidPool();
        pool = pools[pid];
    }
}