// Server-only consumer: no signing, wallet connection, or transactions. These
// are the same finalized Mosaic devnet records used by Highway Shop v3.
import {
  bitmapMember,
  booleanValue,
  numberValue,
  record,
  textValue,
  tokenAmount,
  type RelayerChain,
} from "./relayer.ts";

const DEFAULT_RPC = "https://devnet-gw1.mosaicchain.io/MosaicNode2/chain";
type Api = import("@polkadot/api").ApiPromise;
let apiPromise: Promise<Api> | null = null;
const results = new Map<number, RelayerChain>();
const inflight = new Map<number, Promise<RelayerChain>>();

async function bounded<T>(work: Promise<T>, ms = 18_000): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  try {
    return await Promise.race([
      work,
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("Mosaic registry request timed out.")),
          ms,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer!);
  }
}

async function getApi() {
  if (!apiPromise) {
    apiPromise = (async () => {
      const { ApiPromise, HttpProvider } = await import("@polkadot/api");
      const url = process.env.HIGHWAY_MOSAIC_RPC_URL || DEFAULT_RPC;
      if (new URL(url).protocol !== "https:")
        throw new Error("Mosaic RPC must use HTTPS.");
      const api = new ApiPromise({
        provider: new HttpProvider(url, {}, 0),
        noInitWarn: true,
        throwOnConnect: true,
      });
      try {
        return await bounded(api.isReadyOrError);
      } catch (error) {
        await api.disconnect();
        throw error;
      }
    })();
  }
  try {
    return await apiPromise;
  } catch (error) {
    apiPromise = null;
    throw error;
  }
}

export async function fetchRelayerChain(id: number): Promise<RelayerChain> {
  const existing = results.get(id);
  if (existing && Date.now() - Date.parse(existing.observedAt) < 45_000)
    return existing;
  const pending = inflight.get(id);
  if (pending) return pending;
  const work = bounded(
    (async () => {
      const api = await getApi();
      const hash = await api.rpc.chain.getFinalizedHead();
      const at = await api.at(hash);
      const registry = at.query.highwayRegistry ?? at.query.registry;
      const delegation =
        at.query.highwayNftDelegationRegistry ?? at.query.nftDelegationRegistry;
      if (!registry?.relayers || !registry.activeRelayerSets)
        throw new Error("Mosaic registry metadata has changed.");
      const [rawRelayer, rawSets, header, properties] = await Promise.all([
        registry.relayers(id),
        registry.activeRelayerSets(),
        api.rpc.chain.getHeader(hash),
        api.rpc.system.properties(),
      ]);
      const r = record(rawRelayer.toJSON());
      const sets = rawSets.toJSON();
      const latestSet = Array.isArray(sets)
        ? sets
            .map(record)
            .reduce<Record<string, unknown> | null>(
              (best, next) =>
                numberValue(next.epoch) !== null &&
                (!best || Number(next.epoch) > Number(best.epoch))
                  ? next
                  : best,
              null,
            )
        : null;
      // system_properties is a Json codec; nested values may still be codecs
      // after toJSON(). Serialize once to obtain actual numbers and strings.
      const props = record(JSON.parse(JSON.stringify(properties.toJSON())));
      const decimals = numberValue(
        Array.isArray(props.tokenDecimals)
          ? props.tokenDecimals[0]
          : props.tokenDecimals,
      );
      const symbol =
        textValue(
          Array.isArray(props.tokenSymbol)
            ? props.tokenSymbol[0]
            : props.tokenSymbol,
        ) ?? "TMOS";
      const balance = async (address: string | null) => {
        if (!address || decimals === null) return { free: null, exists: null };
        const [account, size] = await Promise.all([
          at.query.system.account(address),
          at.query.system.account.size(address),
        ]);
        return {
          free: tokenAmount(
            record(record(account.toJSON()).data).free,
            decimals,
          ),
          exists: !size.isZero(),
        };
      };
      const manager = textValue(r.manager),
        beneficiary = textValue(r.beneficiary);
      const keys = Object.entries(record(r.operationalKeys)).flatMap(
        ([chain, values]) =>
          (Array.isArray(values) ? values : [])
            .filter(
              (v): v is string =>
                typeof v === "string" && /^0x[0-9a-f]+$/i.test(v),
            )
            .map((key) => ({
              chain:
                chain === "2"
                  ? "Mosaic"
                  : chain === "3"
                    ? "EVM"
                    : `Chain ${chain}`,
              key,
            })),
      );
      const [rewards, managerAccount, weight, operationalKeys] =
        await Promise.all([
          balance(beneficiary),
          balance(manager),
          delegation?.relayerDelegatedWeight
            ? delegation
                .relayerDelegatedWeight(id)
                .then((v) => tokenAmount(v.toJSON(), 0))
            : null,
          Promise.all(
            keys
              .slice(0, 12)
              .map(async (key) => ({
                ...key,
                balance:
                  key.chain === "Mosaic" ? (await balance(key.key)).free : null,
              })),
          ),
        ]);
      const found = numberValue(r.id) === id;
      const result: RelayerChain = {
        observedAt: new Date().toISOString(),
        block: header.number.toNumber(),
        epoch: numberValue(latestSet?.epoch),
        registered: found,
        authorized: found ? booleanValue(r.isAuthorizedOperator) : false,
        inActiveSet: latestSet
          ? bitmapMember(latestSet.activeSetBitmap, id)
          : null,
        earningWeight: weight,
        rewardsBalance: rewards.free,
        managerBalance: managerAccount.free,
        managerExists: managerAccount.exists,
        tokenSymbol: symbol,
        rewardsWallet: beneficiary,
        managerWallet: manager,
        operationalKeys,
        blsKey: textValue(r.blsKey),
        p2pKey: textValue(r.p2pKey),
      };
      if (results.size >= 200) results.delete(results.keys().next().value!);
      results.set(id, result);
      return result;
    })(),
  );
  inflight.set(id, work);
  try {
    return await work;
  } finally {
    inflight.delete(id);
  }
}

export function lastRelayerChain(id: number) {
  return results.get(id) ?? null;
}
export async function disconnectRelayerChain() {
  if (apiPromise) {
    const api = await apiPromise;
    await api.disconnect();
    apiPromise = null;
  }
}
