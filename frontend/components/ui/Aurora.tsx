/**
 * The hero's background field: teal bleeding into amber, blurred past
 * recognition. Purely decorative, so it is inert to assistive tech and its
 * drift is disabled under reduced-motion by the global rule in globals.css.
 */
export function Aurora() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10 overflow-hidden"
    >
      <div className="absolute inset-0 grid-field opacity-70" />
      <div className="absolute -left-32 -top-40 h-[38rem] w-[38rem] rounded-full bg-yield-500/25 blur-[140px] animate-drift" />
      <div className="absolute -right-40 top-24 h-[34rem] w-[34rem] rounded-full bg-credit-600/20 blur-[150px] animate-drift [animation-delay:-8s]" />
      <div className="absolute left-1/3 top-1/2 h-[26rem] w-[26rem] rounded-full bg-yield-300/10 blur-[130px] animate-drift [animation-delay:-14s]" />
      {/* Settle the field back to void before the next section starts. */}
      <div className="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-b from-transparent to-void" />
    </div>
  );
}
