"use client";

import { useEffect } from "react";

export function LanguageRuntime() {
  useEffect(() => {
    document.documentElement.dataset.sdmAppReady = "true";

    return () => {
      delete document.documentElement.dataset.sdmAppReady;
    };
  }, []);

  return null;
}
