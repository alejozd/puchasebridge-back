const toHeDate = (dateValue) => {
  const d = new Date(dateValue);
  const base = new Date(Date.UTC(1899, 11, 30));
  const utc = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  return Math.floor((utc - base.getTime()) / (24 * 60 * 60 * 1000));
};

const currentYear = () => String(new Date().getFullYear());

module.exports = { toHeDate, currentYear };
