import type { Metadata } from "next";
import "../themes/royal-indigo.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "Aviatrix SIEM Connector",
  description: "Status dashboard for the Aviatrix Log Integration Engine",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="antialiased bg-background-default text-foreground">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
