"use client";

import { Camera, FlaskConical, SquareTerminal, X } from "lucide-react";
import { type Workbench as WorkbenchState } from "./use-workbench";
import { RunPanel } from "./run-panel";
import { HistoryPanel } from "./history-panel";
import { ConfigurationPanel } from "./configuration-panel";
import { DatasetPanel } from "@/features/dataset/dataset-panel";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import {
  Alert,
  AlertDescription,
  AlertTitle,
  AlertAction,
} from "@/components/ui/alert";
import {
  Empty,
  EmptyHeader,
  EmptyTitle,
  EmptyDescription,
} from "@/components/ui/empty";

export function Workbench({
  workbench: w,
  onClose,
}: {
  workbench: WorkbenchState;
  onClose: () => void;
}) {
  const ios = w.runtime?.platform === "ios";
  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh max-w-[1800px] flex-col gap-5 p-4 pt-[max(1rem,env(safe-area-inset-top))] pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-6"
    >
      <Button variant="outline" className="self-start" onClick={onClose}>
        Zurück zu Terminen
      </Button>
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <SquareTerminal className="size-5" aria-hidden="true" />
          <h1 className="text-base font-semibold">Laßnitzhöhe · Diagnose</h1>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant="outline">
            {w.runtime?.platform ?? (w.native ? "native" : "browser")}
          </Badge>
          <Badge variant="secondary">
            {w.native ? "local runtime" : "recorded fixtures"}
          </Badge>
        </div>
      </header>
      <Separator />
      {w.error && (
        <Alert variant="destructive">
          <AlertTitle>Command failed</AlertTitle>
          <AlertDescription>{w.error}</AlertDescription>
          <AlertAction>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Dismiss error"
              onClick={() => w.setError("")}
            >
              <X />
            </Button>
          </AlertAction>
        </Alert>
      )}
      {w.notice && (
        <Alert>
          <AlertDescription>{w.notice}</AlertDescription>
        </Alert>
      )}
      {w.busy && (
        <Alert>
          <AlertTitle role="status">{w.busy}</AlertTitle>
          <AlertAction>
            <Button variant="outline" onClick={w.cancel}>
              Cancel
            </Button>
          </AlertAction>
        </Alert>
      )}
      <Tabs value={w.view} onValueChange={w.setView} className="min-w-0">
        <TabsList>
          <TabsTrigger value="run" disabled={!!w.busy}>
            Run
          </TabsTrigger>
          {!ios && (
            <TabsTrigger value="dataset" disabled={!!w.busy}>
              Dataset
            </TabsTrigger>
          )}
          <TabsTrigger value="history" disabled={!!w.busy}>
            History
          </TabsTrigger>
          <TabsTrigger value="configuration" disabled={!!w.busy}>
            Configuration
          </TabsTrigger>
        </TabsList>
        <TabsContent value="run" className="flex min-w-0 flex-col gap-5">
          <FieldGroup className="sm:flex-row sm:items-end">
            <Field className="sm:max-w-56">
              <FieldLabel htmlFor="engine">Engine</FieldLabel>
              <Select
                value={w.config.engine}
                onValueChange={(engine) => w.setConfig({ ...w.config, engine })}
                disabled={!!w.busy}
              >
                <SelectTrigger id="engine">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectGroup>
                    {[
                      "portable-small",
                      "portable-tiny",
                      "portable-medium",
                      ...(ios ? ["apple-vision"] : []),
                    ].map((engine) => (
                      <SelectItem key={engine} value={engine}>
                        {engine}
                      </SelectItem>
                    ))}
                  </SelectGroup>
                </SelectContent>
              </Select>
            </Field>
            <Field className="sm:max-w-sm">
              <FieldLabel htmlFor="image-import">Input images</FieldLabel>
              <Input
                id="image-import"
                type="file"
                accept=".jpg,.jpeg,.png,.heic,.heif,image/jpeg,image/png,image/heic,image/heif"
                multiple
                disabled={!w.native || !!w.busy}
                onChange={(event) => {
                  const files = Array.from(event.target.files ?? []);
                  event.target.value = "";
                  if (files.length) void w.importFiles(files);
                }}
              />
            </Field>
            <div className="flex flex-wrap gap-2">
              {ios && (
                <>
                  <Button
                    variant="outline"
                    disabled={!!w.busy}
                    onClick={() => w.capture("camera")}
                  >
                    <Camera data-icon="inline-start" />
                    Camera
                  </Button>
                  <Button
                    variant="outline"
                    disabled={!!w.busy}
                    onClick={() => w.capture("photos")}
                  >
                    Photos
                  </Button>
                </>
              )}
              <Button variant="outline" disabled={!!w.busy} onClick={w.sample}>
                <FlaskConical data-icon="inline-start" />
                Load fixture
              </Button>
            </div>
          </FieldGroup>
          <Separator />
          {w.run ? (
            <RunPanel key={w.run.id} workbench={w} run={w.run} />
          ) : (
            <Empty className="min-h-56">
              <EmptyHeader>
                <EmptyTitle>No active run</EmptyTitle>
                <EmptyDescription>
                  {w.native
                    ? "Import an image or process the synthetic fixture."
                    : "Load the recorded fixture, or start Tauri for local inference."}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
        </TabsContent>
        <TabsContent value="dataset">
          <DatasetPanel workbench={w} />
        </TabsContent>
        <TabsContent value="history">
          <HistoryPanel workbench={w} />
        </TabsContent>
        <TabsContent value="configuration">
          <ConfigurationPanel
            key={JSON.stringify(w.preferences)}
            workbench={w}
          />
        </TabsContent>
      </Tabs>
    </main>
  );
}
