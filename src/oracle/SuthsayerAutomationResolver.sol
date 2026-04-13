// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISuthsayerPredictionMarket {
    enum Outcome {
        Unresolved,
        Yes,
        No,
        Invalid
    }

    function resolveMarket(bytes32 marketId, Outcome outcome) external;
}

contract SuthsayerAutomationResolver {
    address public owner;
    ISuthsayerPredictionMarket public predictionMarket;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address predictionMarket_) {
        owner = msg.sender;
        predictionMarket = ISuthsayerPredictionMarket(predictionMarket_);
    }

    function resolveManually(bytes32 marketId, uint8 outcome) external onlyOwner {
        require(outcome >= 1 && outcome <= 3, "bad outcome");
        predictionMarket.resolveMarket(
            marketId,
            ISuthsayerPredictionMarket.Outcome(outcome)
        );
    }
}