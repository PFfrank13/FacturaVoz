import Image from "next/image";

type Method = "yape" | "plin" | "tarjeta";

export function PaymentMark({ method, size = 26 }: { method: Method; size?: number }) {
  if (method === "tarjeta") {
    return (
      <svg aria-hidden="true" width={size} height={size} viewBox="0 0 56 56" fill="none" className="shrink-0">
        <rect x="1.5" y="10.5" width="53" height="34" rx="5.5" fill="#263755" stroke="#8496B1" />
        <rect x="7" y="19" width="12" height="9" rx="2" fill="#F3CD88" />
        <path d="M7 23.5h3.5L12 21.5V19m0 9v-2.5l-1.5-2M19 23.5h-3.5" stroke="#8B643B" />
        <path d="M43.3 19.7a4 4 0 0 1 0 4.6m2.4-6.4a7 7 0 0 1 0 8.2m2.4-9.9a10 10 0 0 1 0 11.6M8 36h6m5 0h6m5 0h6m5 0h6" stroke="#E5EDF5" strokeWidth="1.6" strokeLinecap="round" />
      </svg>
    );
  }
  return (
    <Image
      src={`/app/assets/assets/payments/${method}.png`}
      alt=""
      width={size}
      height={size}
      unoptimized
      className={method === "yape" ? "shrink-0 rounded-[22%]" : "shrink-0"}
    />
  );
}
