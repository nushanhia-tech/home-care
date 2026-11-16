export function toPaise(value) {
  const text = String(value ?? "");
  if (!/^\d{1,8}(\.\d{1,2})?$/.test(text))
    throw new Error("Enter an INR amount with at most two decimal places.");
  const [whole, fraction = ""] = text.split(".");
  const amount = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  if (amount > 1000000000) throw new Error("Amount is too large.");
  return amount;
}
export const inr = (paise) =>
  "₹" +
  (Number(paise || 0) / 100).toLocaleString("en-IN", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
