"use client";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import KagentLogo from "./kagent-logo";

export default function KAgentLogoWithText({ className } : { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return null;
  }

  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <KagentLogo className="h-full w-auto aspect-[378/286]" />
      <span className="font-bold text-xl tracking-tight">Maduro</span>
    </div>
  );
}
