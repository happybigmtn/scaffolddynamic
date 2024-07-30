"use client";

import { useEffect, useState } from "react";
import { ethers } from "ethers";
import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { Address, AddressInput } from "~~/components/scaffold-eth";
import {
  useDeployedContractInfo,
  useScaffoldEventHistory,
  useScaffoldReadContract,
  useScaffoldWatchContractEvent,
  useScaffoldWriteContract,
} from "~~/hooks/scaffold-eth";

const Home: NextPage = () => {
  const { address } = useAccount();
  const [betAmount, setBetAmount] = useState<string>("");
  const [betType, setBetType] = useState<number>(0);
  const [isLoading, setIsLoading] = useState(false);
  const [nextClaimTime, setNextClaimTime] = useState<Date | null>(null);
  const [freeBalance, setFreeBalance] = useState<string>("0");
  const [gameResult, setGameResult] = useState<string | null>(null);
  const [gameHistory, setGameHistory] = useState<string[]>([]);
  const [approvalAmount, setApprovalAmount] = useState<string>("");
  const [handResults, setHandResults] = useState<{ playerHand: number[]; bankerHand: number[] } | null>(null);

  const { writeContractAsync: placeBet } = useScaffoldWriteContract("BaccaratGame");
  const { writeContractAsync: claimTokens } = useScaffoldWriteContract("FreeChips");
  const { writeContractAsync: approveTokens } = useScaffoldWriteContract("FreeChips");
  const { data: nextClaimTimeData, refetch: refetchNextClaimTime } = useScaffoldReadContract({
    contractName: "FreeChips",
    functionName: "getNextClaimTime",
    args: [address],
  });

  const { data: freeBalanceData, refetch: refetchFreeBalance } = useScaffoldReadContract({
    contractName: "FreeChips",
    functionName: "balanceOf",
    args: [address],
  });

  const { data: baccaratGameContract } = useDeployedContractInfo("BaccaratGame");

  const { data: allowanceData, refetch: refetchAllowance } = useScaffoldReadContract({
    contractName: "FreeChips",
    functionName: "allowance",
    args: [address, baccaratGameContract?.address],
  });

  useEffect(() => {
    if (nextClaimTimeData) {
      setNextClaimTime(new Date(Number(nextClaimTimeData) * 1000));
    }
  }, [nextClaimTimeData]);

  useEffect(() => {
    if (freeBalanceData) {
      setFreeBalance(ethers.utils.formatUnits(freeBalanceData, 18));
    }
  }, [freeBalanceData]);

  useScaffoldWatchContractEvent({
    contractName: "BaccaratGame",
    eventName: "GameCompleted",
    listener: (gameId, winner, playerHand, bankerHand) => {
      const result = `Game ${gameId} completed. Winner: ${["Player", "Banker", "Tie"][winner]}`;
      setGameResult(result);
      setGameHistory(prev => [result, ...prev.slice(0, 4)]);
      setHandResults({ playerHand: playerHand.map(Number), bankerHand: bankerHand.map(Number) });
    },
  });

  useScaffoldWatchContractEvent({
    contractName: "BaccaratGame",
    eventName: "Payout",
    listener: (player, amount) => {
      if (player === address) {
        const result = `You won ${ethers.utils.formatUnits(amount, 18)} FREE!`;
        setGameResult(result);
        setGameHistory(prev => [result, ...prev.slice(0, 4)]);
        refetchFreeBalance();
      }
    },
  });

  const { data: pastEvents } = useScaffoldEventHistory({
    contractName: "BaccaratGame",
    eventName: "GameCompleted",
    fromBlock: Number(process.env.NEXT_PUBLIC_DEPLOY_BLOCK) || 0,
    toBlock: "latest",
    blockData: true,
  });

  useEffect(() => {
    if (pastEvents) {
      const formattedEvents = pastEvents.map(
        event =>
          `Game ${event.args.gameId} completed. Winner: ${["Player", "Banker", "Tie"][event.args.winner]} (Block: ${
            event.blockNumber
          })`,
      );
      setGameHistory(formattedEvents.slice(0, 5));
    }
  }, [pastEvents]);

  const handlePlaceBet = async () => {
    if (!betAmount) return;
    setIsLoading(true);
    try {
      // Generate a random commitment
      const commitment = ethers.utils.randomBytes(32);

      await placeBet({
        functionName: "placeBet",
        args: [betType, ethers.utils.parseUnits(betAmount, 18), commitment],
      });
      console.log("Bet placed successfully!");
      setGameResult(null);
    } catch (error) {
      console.error("Error placing bet:", error);
      setGameResult("Error placing bet. Please try again.");
    } finally {
      setIsLoading(false);
      refetchFreeBalance();
      refetchAllowance();
    }
  };

  const handleClaimTokens = async () => {
    setIsLoading(true);
    try {
      await claimTokens({ functionName: "claimTokens" });
      console.log("Tokens claimed successfully!");
      refetchNextClaimTime();
      refetchFreeBalance();
    } catch (error) {
      console.error("Error claiming tokens:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleApproveTokens = async () => {
    if (!approvalAmount || !baccaratGameContract) return;
    setIsLoading(true);
    try {
      await approveTokens({
        functionName: "approve",
        args: [baccaratGameContract.address, ethers.utils.parseUnits(approvalAmount, 18)],
      });
      console.log("Tokens approved successfully!");
      refetchAllowance();
    } catch (error) {
      console.error("Error approving tokens:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const canClaimTokens = nextClaimTime ? new Date() >= nextClaimTime : false;

  return (
    <div className="flex items-center flex-col flex-grow pt-10">
      <div className="px-5">
        <h1 className="text-center mb-8">
          <span className="block text-2xl mb-2">Welcome to</span>
          <span className="block text-4xl font-bold">Baccarat Game</span>
        </h1>
        <div className="flex justify-center items-center space-x-2 flex-col sm:flex-row">
          <p className="my-2 font-medium">Connected Address:</p>
          <Address address={address} />
        </div>
        <div className="mt-4 text-center">
          <p className="font-medium">Your FREE Balance: {freeBalance} FREE</p>
          <p className="font-medium">
            Current Allowance: {allowanceData ? ethers.utils.formatUnits(allowanceData, 18) : "0"} FREE
          </p>
        </div>
        <div className="mt-8 flex flex-col items-center">
          <button className="btn btn-primary mb-4" onClick={handleClaimTokens} disabled={!canClaimTokens || isLoading}>
            {isLoading ? "Claiming..." : "Claim FREE Tokens"}
          </button>
          {nextClaimTime && <p className="text-sm mb-4">Next claim available: {nextClaimTime.toLocaleString()}</p>}
          <AddressInput
            value={approvalAmount}
            placeholder="Approval Amount (FREE)"
            onChange={value => setApprovalAmount(value)}
          />
          <button className="btn btn-secondary mb-4" onClick={handleApproveTokens} disabled={isLoading}>
            {isLoading ? "Approving..." : "Approve FREE Tokens"}
          </button>
          <AddressInput value={betAmount} placeholder="Bet Amount (FREE)" onChange={value => setBetAmount(value)} />
          <select
            value={betType}
            onChange={e => setBetType(Number(e.target.value))}
            className="select select-bordered w-full max-w-xs my-4"
          >
            <option value={0}>Player</option>
            <option value={1}>Banker</option>
            <option value={2}>Tie</option>
          </select>
          <button className="btn btn-primary" onClick={handlePlaceBet} disabled={isLoading}>
            {isLoading ? "Placing Bet..." : "Place Bet"}
          </button>
          {gameResult && <p className="mt-4 text-lg font-semibold">{gameResult}</p>}
          {handResults && (
            <div className="mt-4">
              <p>Player Hand: {handResults.playerHand.join(", ")}</p>
              <p>Banker Hand: {handResults.bankerHand.join(", ")}</p>
            </div>
          )}
          <div className="mt-8">
            <h2 className="text-xl font-bold mb-2">Recent Games</h2>
            <ul>
              {gameHistory.map((game, index) => (
                <li key={index} className="mb-1">
                  {game}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
