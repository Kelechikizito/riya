import type { ReactNode } from "react";

/**
 * One page section. Sections carry generous vertical rhythm (96–144px) because
 * the density dial for this page is deliberately low — each idea gets its own
 * screen rather than competing with the next.
 */
export function Section({
  id,
  eyebrow,
  title,
  lede,
  children,
  className = "",
  align = "left",
}: {
  id?: string;
  eyebrow?: string;
  title?: ReactNode;
  lede?: ReactNode;
  children?: ReactNode;
  className?: string;
  align?: "left" | "center";
}) {
  const centered = align === "center";
  return (
    <section
      id={id}
      className={`mx-auto w-full max-w-6xl scroll-mt-24 px-5 py-24 sm:px-8 sm:py-32 ${className}`}
    >
      {(eyebrow || title || lede) && (
        <div className={`max-w-2xl ${centered ? "mx-auto text-center" : ""}`}>
          {eyebrow && <p className="eyebrow mb-4">{eyebrow}</p>}
          {title && (
            <h2 className="text-[1.75rem] font-semibold leading-[1.15] sm:text-[2.375rem]">
              {title}
            </h2>
          )}
          {lede && (
            <p className="mt-5 text-[17px] leading-relaxed text-muted sm:text-[19px]">
              {lede}
            </p>
          )}
        </div>
      )}
      {children && <div className={title ? "mt-14" : ""}>{children}</div>}
    </section>
  );
}
