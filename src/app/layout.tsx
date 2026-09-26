import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Laßnitzhöhe",
  description: "Terminpläne lokal erfassen und prüfen",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="de">
      <body>{children}</body>
    </html>
  );
}
