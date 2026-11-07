export default function Brand({ product = "Control" }: { product?: "Control" | "POS" }) {
  return <span className="sr-brand"><svg width="44" height="44" viewBox="0 0 64 64" aria-hidden="true">
    <rect width="64" height="64" rx="16" fill="#102f32" />
    <path d="M19 43V29M28 49V17M37 43V23M46 38V28" stroke="#c9f27a" strokeWidth="6" strokeLinecap="round" />
  </svg><span><strong>FacturaVoz</strong><small>{product} / Solvex Software Labs</small></span></span>;
}
