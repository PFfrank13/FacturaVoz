export default function Brand({ product = "Control" }: { product?: "Control" | "POS" }) {
  return <span className="sr-brand"><svg width="44" height="44" viewBox="0 0 64 64" aria-hidden="true">
    <rect width="64" height="64" rx="16" fill="#102f32" />
    <path d="M16 15H48V24H25V29H16Z" fill="#c9f27a" />
    <path d="M16 35H39V30H48V49H16V40H39V44H16Z" fill="white" />
  </svg><span><strong>Solvex Retail</strong><small>{product} / Solvex Software Labs</small></span></span>;
}
