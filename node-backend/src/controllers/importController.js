const { parseInvoice } = require('../utils/xmlParser');
const { obtenerProveedorPorNit } = require('../repositories/proveedorRepository');
const { existeProducto } = require('../repositories/productoRepository');

const postFacturaXml = async (req, res) => {
  const xmlContent = req.body;
  if (!xmlContent) return res.status(400).send('Cuerpo XML vacío');

  const parsed = parseInvoice(xmlContent);
  const anio = String(new Date(parsed.fechaEmision).getFullYear());

  const proveedor = await obtenerProveedorPorNit(parsed.provider.nit, anio);
  const productos = await Promise.all(
    parsed.products.map(async (p) => ({ referencia: p.referencia, descripcion: p.descripcion, existe: await existeProducto(p.referencia, p.descripcion, anio) })),
  );

  return res.json({ proveedor: { nit: parsed.provider.nit, existe: proveedor.existe, ...(proveedor.existe ? { codigo: proveedor.codigo } : {}) }, productos });
};

module.exports = { postFacturaXml };
