"use client";

import { useSyncExternalStore } from "react";

const noopSubscribe = () => () => {};

/**
 * False during SSR and the first client render, true afterwards.
 *
 * Anything that depends on browser-only state — an injected wallet, a media
 * query — has to render its server-safe shape first or React reports a
 * hydration mismatch. `useSyncExternalStore` expresses that directly, without
 * the setState-in-an-effect that a `mounted` flag would need.
 */
export function useHydrated(): boolean {
  return useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
}

/** Subscribes to a media query, SSR-safe. Returns false until hydrated. */
export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener("change", onChange);
      return () => mql.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

export function usePrefersReducedMotion(): boolean {
  return useMediaQuery("(prefers-reduced-motion: reduce)");
}
