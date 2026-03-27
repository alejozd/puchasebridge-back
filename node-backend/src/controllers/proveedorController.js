const { obtenerProveedorPorNit } = require('../repositories/proveedorRepository');

const getProveedor = async (req, res) => {
  const proveedor = await obtenerProveedorPorNit(req.params.nit, req.query.anio || '');
  return res.json(proveedor.existe ? { existe: true, codigo: proveedor.codigo } : { existe: false });
};

module.exports = { getProveedor };
