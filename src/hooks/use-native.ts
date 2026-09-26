"use client";

import { useSyncExternalStore } from "react";
import { isTauri } from "@/lib/native";

const subscribe = () => () => {};
const serverSnapshot = () => false;

export function useNative() {
  return useSyncExternalStore(subscribe, isTauri, serverSnapshot);
}
