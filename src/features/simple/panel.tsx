"use client";
import { useEffect, useSyncExternalStore, type ReactNode } from "react";
import { X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
const subscribe = (cb: () => void) => {
  const q = matchMedia("(min-width: 768px)");
  q.addEventListener("change", cb);
  return () => q.removeEventListener("change", cb);
};
export function Panel({
  title,
  description,
  onClose,
  children,
  actions,
}: {
  title: string;
  description?: string;
  onClose: () => void;
  children: ReactNode;
  actions?: ReactNode;
}) {
  const desktop = useSyncExternalStore(
    subscribe,
    () => matchMedia("(min-width: 768px)").matches,
    () => false,
  );
  useEffect(() => {
    const viewport = window.visualViewport;
    const update = () => {
      document.documentElement.style.setProperty(
        "--visible-height",
        `${viewport?.height ?? window.innerHeight}px`,
      );
      document.documentElement.style.setProperty(
        "--keyboard-inset",
        `${Math.max(0, window.innerHeight - (viewport?.height ?? window.innerHeight) - (viewport?.offsetTop ?? 0))}px`,
      );
    };
    update();
    viewport?.addEventListener("resize", update);
    viewport?.addEventListener("scroll", update);
    return () => {
      viewport?.removeEventListener("resize", update);
      viewport?.removeEventListener("scroll", update);
    };
  }, []);
  return (
    <Sheet
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <SheetContent
        side={desktop ? "right" : "bottom"}
        showCloseButton={false}
        className="simple-panel simple-interface"
        onCloseAutoFocus={(event) => {
          event.preventDefault();
          document.getElementById("review-focus")?.focus();
        }}
      >
        <SheetHeader className="shrink-0 pr-16">
          <SheetTitle>{title}</SheetTitle>
          <SheetDescription className={description ? undefined : "sr-only"}>
            {description ?? title}
          </SheetDescription>
          <Button
            variant="ghost"
            size="icon"
            className="absolute top-3 right-3"
            aria-label="Schließen"
            onClick={onClose}
          >
            <X />
          </Button>
        </SheetHeader>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-5">
          {children}
        </div>
        {actions && (
          <SheetFooter className="shrink-0 border-t bg-background">
            {actions}
          </SheetFooter>
        )}
      </SheetContent>
    </Sheet>
  );
}
