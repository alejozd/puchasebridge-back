const { XMLParser } = require('fast-xml-parser');

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  parseAttributeValue: true,
  trimValues: true,
});

const toArray = (val) => (Array.isArray(val) ? val : val ? [val] : []);
const local = (name = '') => (name.includes(':') ? name.split(':')[1] : name);

const getByLocalName = (obj, target) => {
  if (!obj || typeof obj !== 'object') return undefined;
  for (const [key, value] of Object.entries(obj)) {
    if (local(key) === target) return value;
  }
  return undefined;
};

const findRecursive = (obj, target) => {
  if (!obj || typeof obj !== 'object') return undefined;
  const direct = getByLocalName(obj, target);
  if (direct !== undefined) return direct;
  for (const value of Object.values(obj)) {
    if (typeof value === 'object') {
      const found = findRecursive(value, target);
      if (found !== undefined) return found;
    }
  }
  return undefined;
};

const asNumber = (v) => {
  const n = Number(String(v ?? '0').replace(/,/g, ''));
  return Number.isFinite(n) ? n : 0;
};

const parseInvoice = (xmlContent) => {
  const doc = parser.parse(xmlContent);
  const rootKey = Object.keys(doc)[0];
  let root = doc[rootKey];

  if (local(rootKey) === 'AttachedDocument') {
    const description = findRecursive(root, 'Description');
    if (typeof description === 'string' && description.includes('<Invoice')) {
      const inner = parser.parse(description);
      root = inner[Object.keys(inner)[0]];
    }
  }

  const supplierParty = getByLocalName(root, 'AccountingSupplierParty');
  const party = getByLocalName(supplierParty, 'Party');
  const taxScheme = getByLocalName(party, 'PartyTaxScheme');
  const companyIdNode = getByLocalName(taxScheme, 'CompanyID');

  const provider = {
    nit: typeof companyIdNode === 'object' ? String(companyIdNode['#text'] || '') : String(companyIdNode || ''),
    nombre: '',
    nombreLegal: String(getByLocalName(taxScheme, 'RegistrationName') || ''),
    tipoIdentificacion: typeof companyIdNode === 'object' ? String(companyIdNode['@_schemeName'] || companyIdNode['@_schemeID'] || '') : '',
    direccion: '',
  };

  const partyName = getByLocalName(party, 'PartyName');
  provider.nombre = String(getByLocalName(partyName, 'Name') || '');
  const partyLegalEntity = getByLocalName(party, 'PartyLegalEntity');
  const legalRegName = getByLocalName(partyLegalEntity, 'RegistrationName');
  if (!provider.nombre) provider.nombre = String(legalRegName || '');
  if (!provider.nombreLegal) provider.nombreLegal = String(legalRegName || '');

  const physicalLoc = getByLocalName(party, 'PhysicalLocation');
  const address = getByLocalName(physicalLoc, 'Address') || getByLocalName(taxScheme, 'RegistrationAddress');
  const addrLine = getByLocalName(address, 'AddressLine');
  provider.direccion = String(getByLocalName(addrLine, 'Line') || '');

  const lines = toArray(getByLocalName(root, 'InvoiceLine'));
  const products = lines.map((line) => {
    const item = getByLocalName(line, 'Item');
    const sellers = getByLocalName(item, 'SellersItemIdentification');
    const standard = getByLocalName(item, 'StandardItemIdentification');
    const qtyNode = getByLocalName(line, 'InvoicedQuantity');
    const taxTotal = getByLocalName(line, 'TaxTotal');
    const taxSubtotal = getByLocalName(taxTotal, 'TaxSubtotal');
    const taxCategory = getByLocalName(taxSubtotal, 'TaxCategory');
    const allowance = getByLocalName(line, 'AllowanceCharge');
    const price = getByLocalName(line, 'Price');

    const quantity = typeof qtyNode === 'object' ? asNumber(qtyNode['#text']) : asNumber(qtyNode);
    return {
      idLinea: String(getByLocalName(line, 'ID') || ''),
      descripcion: String(getByLocalName(item, 'Description') || ''),
      referencia: String(getByLocalName(sellers, 'ID') || ''),
      referenciaEstandar: String(getByLocalName(standard, 'ID') || ''),
      cantidad: quantity,
      unidad: typeof qtyNode === 'object' ? String(qtyNode['@_unitCode'] || '') : '',
      precioBase: asNumber(getByLocalName(price, 'PriceAmount')),
      valorUnitario: asNumber(getByLocalName(price, 'PriceAmount')),
      valorTotal: asNumber(getByLocalName(line, 'LineExtensionAmount')),
      impuesto: asNumber(getByLocalName(taxTotal, 'TaxAmount')),
      impuestoPorcentaje: asNumber(getByLocalName(taxCategory, 'Percent')),
      descuento: String(getByLocalName(allowance, 'ChargeIndicator')).toLowerCase() === 'false' ? asNumber(getByLocalName(allowance, 'Amount')) : 0,
      descuentoPorcentaje:
        String(getByLocalName(allowance, 'ChargeIndicator')).toLowerCase() === 'false'
          ? asNumber(getByLocalName(allowance, 'MultiplierFactorNumeric'))
          : 0,
    };
  });

  const legalTotal = getByLocalName(root, 'LegalMonetaryTotal');
  const taxTotal = getByLocalName(root, 'TaxTotal');
  const issueDate = String(getByLocalName(root, 'IssueDate') || '');

  return {
    provider,
    products,
    totals: {
      subtotal: asNumber(getByLocalName(legalTotal, 'LineExtensionAmount')),
      taxExclusiveAmount: asNumber(getByLocalName(legalTotal, 'TaxExclusiveAmount')),
      taxInclusiveAmount: asNumber(getByLocalName(legalTotal, 'TaxInclusiveAmount')),
      impuestoTotal: asNumber(getByLocalName(taxTotal, 'TaxAmount')),
      total: asNumber(getByLocalName(legalTotal, 'PayableAmount')),
    },
    fechaEmision: issueDate ? new Date(issueDate) : new Date(),
  };
};

module.exports = { parseInvoice };
