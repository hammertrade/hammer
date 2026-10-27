// Calldata for the first buy of the coin through Uniswap's Universal Router: exactly ETH_IN wei of ETH
// in, the coin out straight to RECIPIENT. tools/launch-coin.sh sends it right behind the launch.
//
//   node tools/first-buy.mjs <coin> <hook> <eth-in-wei> <recipient> <deadline>
//
// Prints the calldata for UniversalRouter.execute (0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af).
import { createRequire } from "node:module";
const require = createRequire(new URL("../relayer/package.json", import.meta.url));
const { encodeAbiParameters, encodeFunctionData, encodePacked, parseAbiParameters } = require("viem");

const [coin, hook, ethIn, recipient, deadline] = process.argv.slice(2);
if (!deadline) throw Error("usage: node tools/first-buy.mjs <coin> <hook> <eth-in-wei> <recipient> <deadline>");
const ETH = "0x0000000000000000000000000000000000000000";
// The pool LaunchCoin opens: ETH/coin, 1% fee, tick spacing 200, the fee hook (tools/launch-coin.sh).
const key = { currency0: ETH, currency1: coin, fee: 10000, tickSpacing: 200, hooks: hook };

const swap = encodeAbiParameters(
  parseAbiParameters("((address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 amountIn, uint128 amountOutMinimum, bytes hookData)"),
  [{ poolKey: key, zeroForOne: true, amountIn: BigInt(ethIn), amountOutMinimum: 0n, hookData: "0x" }],
);
const settle = encodeAbiParameters(parseAbiParameters("address, uint256"), [ETH, BigInt(ethIn)]);
// TAKE with amount 0 takes the whole amount owed, to the recipient (not to the sender).
const take = encodeAbiParameters(parseAbiParameters("address, address, uint256"), [coin, recipient, 0n]);
// SWAP_EXACT_IN_SINGLE (0x06), SETTLE_ALL (0x0c), TAKE (0x0e)
const actions = encodePacked(["uint8", "uint8", "uint8"], [0x06, 0x0c, 0x0e]);
const v4 = encodeAbiParameters(parseAbiParameters("bytes, bytes[]"), [actions, [swap, settle, take]]);
console.log(encodeFunctionData({
  abi: [{ type: "function", name: "execute", stateMutability: "payable", inputs: [{ type: "bytes" }, { type: "bytes[]" }, { type: "uint256" }], outputs: [] }],
  functionName: "execute",
  args: ["0x10", [v4], BigInt(deadline)], // V4_SWAP
}));
