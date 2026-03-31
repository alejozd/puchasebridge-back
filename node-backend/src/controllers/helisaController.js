const { buscarProductos } = require('../repositories/productoRepository');

const getProductos = async (req, res) => {
  const filtro = String(req.query.filtro || '').trim();
  if (!filtro) return res.status(400).json({ error: 'El parámetro "filtro" es obligatorio' });
  if (filtro.length < 3) return res.status(400).json({ error: 'El filtro debe tener al menos 3 caracteres' });

  const rows = await buscarProductos(filtro, Number(req.query.limite || 20), String(req.query.anio || ''));
  return res.json({
    productos: rows.map((r) => ({ codigo: r.CODIGO, subcodigo: r.SUBCODIGO, nombre: r.NOMBRE, referencia: r.REFERENCIA, unidad: String(r.UNIDAD || '') })),
  });
};

module.exports = { getProductos };
