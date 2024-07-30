// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract FreeChips is Initializable, ERC20Upgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, ERC20PermitUpgradeable {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens with 18 decimals
    uint256 private constant L1_BLOCKS_PER_YEAR = 31_557_600 / 12; // ≈ 2,629,800
    uint256 public constant TOKENS_PER_BLOCK = 10 * 10**18; // 1 token per L2 block with 18 decimals
    uint256 public constant CLAIM_COOLDOWN = 43200; // 24 hours, assuming 2-second L2 blocks

    uint256 public lastUpdateL2Block;
    uint256 public accumulatedTokens;
    uint256 public currentEpoch;

    struct Claim {
        uint256 epoch;
        uint256 amount;
    }

    mapping(address => Claim) public userClaims;
    mapping(uint256 => uint256) public epochClaimants;
    mapping(uint256 => uint256) public epochTotalTokens;
    mapping(address => uint256) public lastClaimTime;
    event TokensClaimed(address indexed user, uint256 amount, uint256 epoch);
    event TokensAccumulated(uint256 newTokens, uint256 totalAccumulated);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) initializer public {
        __ERC20_init("FreeChips", "FREE");
        __ERC20Pausable_init();
        __Ownable_init(initialOwner);
        __ERC20Permit_init("FreeChips");

        _mint(initialOwner, INITIAL_SUPPLY);
        lastUpdateL2Block = block.number;
        currentEpoch = getCurrentEpoch();
    }

    function claimTokens() external whenNotPaused {
        require(block.timestamp >= lastClaimTime[msg.sender] + CLAIM_COOLDOWN, "Must wait 24 hours between claims");

        uint256 tokensToDistribute = TOKENS_PER_BLOCK * CLAIM_COOLDOWN;
        _mint(msg.sender, tokensToDistribute);

        lastClaimTime[msg.sender] = block.timestamp;
        emit TokensClaimed(msg.sender, tokensToDistribute, getCurrentEpoch());
    }

    function getNextClaimTime(address user) public view returns (uint256) {
        return lastClaimTime[user] + CLAIM_COOLDOWN;
    }

    function _distributePreviousEpochs(uint256 newCurrentEpoch) internal {
        for (uint256 epoch = currentEpoch + 1; epoch <= newCurrentEpoch; epoch++) {
            if (epochClaimants[epoch] == 0) continue;

            uint256 tokensToDistribute = TOKENS_PER_BLOCK * CLAIM_COOLDOWN;
            if (epoch == newCurrentEpoch) {
                tokensToDistribute += accumulatedTokens;
                accumulatedTokens = 0;
            }
            
            epochTotalTokens[epoch] = tokensToDistribute;
        }
    }

    function batchDistributeClaims(address[] calldata claimants) external whenNotPaused {
        for (uint i = 0; i < claimants.length; i++) {
            address claimant = claimants[i];
            Claim storage userClaim = userClaims[claimant];
            
            if (userClaim.epoch < currentEpoch && userClaim.amount == 0) {
                uint256 totalAmount = 0;
                for (uint256 epoch = userClaim.epoch + 1; epoch <= currentEpoch; epoch++) {
                    if (epochClaimants[epoch] > 0) {
                        totalAmount += epochTotalTokens[epoch] / epochClaimants[epoch];
                    }
                }
                userClaim.amount = totalAmount;
                _mint(claimant, totalAmount);
                emit TokensClaimed(claimant, totalAmount, currentEpoch);
            }
        }
    }

    function _updateAccumulatedTokens() internal {
        uint256 currentL2Block = block.number;
        uint256 elapsedBlocks = currentL2Block - lastUpdateL2Block;
        if (elapsedBlocks > 0) {
            uint256 newTokens = elapsedBlocks * TOKENS_PER_BLOCK;
            accumulatedTokens += newTokens;
            lastUpdateL2Block = currentL2Block;
            emit TokensAccumulated(newTokens, accumulatedTokens);
        }
    }

    function getCurrentEpoch() public view returns (uint256) {
        return block.number / CLAIM_COOLDOWN;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }
}