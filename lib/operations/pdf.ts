import { PDFDocument, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import { readFile } from "node:fs/promises";
import path from "node:path";
export async function invoicePDF(record: any) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const bytes = await readFile(
    path.join(process.cwd(), "assets/fonts/NotoSans-Regular.ttf"),
  );
  const font = await pdf.embedFont(bytes, { subset: true });
  let page = pdf.addPage([595, 842]),
    y = 790;
  const write = (text: string, size = 11, color = rgb(0.1, 0.18, 0.28)) => {
    const safe = String(text || "").replace(/[\r\n]+/g, " ");
    const words = safe.split(" ");
    let line = "";
    for (const word of words) {
      if (
        font.widthOfTextAtSize((line ? line + " " : "") + word, size) > 490 &&
        line
      ) {
        if (y < 60) {
          page = pdf.addPage([595, 842]);
          y = 790;
        }
        page.drawText(line, { x: 50, y, size, font, color });
        y -= size + 7;
        line = word;
      } else line += (line ? " " : "") + word;
    }
    if (line) {
      if (y < 60) {
        page = pdf.addPage([595, 842]);
        y = 790;
      }
      page.drawText(line, { x: 50, y, size, font, color });
      y -= size + 9;
    }
  };
  const data = record.snapshot;
  page.drawRectangle({
    x: 50,
    y: 779,
    width: 26,
    height: 26,
    color: rgb(0.03, 0.6, 0.9),
  });
  page.drawText("LM", { x: 53, y: 787, size: 11, font, color: rgb(1, 1, 1) });
  y = 755;
  write(data.platform_name || "LOCAL MATE", 22, rgb(0.03, 0.5, 0.8));
  write("SERVICE INVOICE", 14);
  write(
    record.number +
      " | " +
      new Date(record.issued_at).toLocaleDateString("en-IN", {
        timeZone: "Asia/Kolkata",
      }),
  );
  write("Booking: " + data.booking_id);
  write("Invoice status: " + record.status);
  y -= 8;
  write("Customer: " + data.customer_name);
  write(data.customer_address);
  write("Provider: " + data.provider_name);
  write("Service area: " + (data.provider_locations || []).join(", "));
  write(data.platform_address);
  y -= 10;
  write(data.service_name, 15);
  write(data.description);
  y -= 12;
  for (const item of record.items || [])
    write(item.label + ": INR " + (Number(item.amount_paise) / 100).toFixed(2));
  y -= 8;
  write("TOTAL: INR " + (Number(data.total_paise) / 100).toFixed(2), 16);
  if (Number(data.tax_paise) > 0)
    write(
      "Tax " + data.tax_percent + "% | Registration: " + data.tax_registration,
    );
  write("Payment method: " + data.payment_method);
  write("Payment status: " + record.payment_status.toUpperCase());
  if (record.payment_status !== "successful")
    write("This invoice is not proof of payment.");
  y -= 12;
  write(data.terms, 9);
  pdf.setTitle(record.number);
  pdf.setAuthor(data.platform_name || "Local Mate");
  return Buffer.from(await pdf.save());
}
