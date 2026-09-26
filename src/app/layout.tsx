import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Reha Calendar Lab",
  description: "Local schedule recognition workbench",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
