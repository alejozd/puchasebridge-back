const { obtenerProveedorPorNit } = require('../repositories/proveedorRepository');
const { existeEquivalencia } = require('../repositories/equivalenciaRepository');

const validarDocumento = async (parsedInvoice) => {
  const errores = [];
  const proveedorInfo = await obtenerProveedorPorNit(parsedInvoice.proveedor.nit, '');
  const proveedorExiste = proveedorInfo.existe;

  if (!proveedorExiste) errores.push('Proveedor no existe en Helisa');

  let todosProductosExisten = true;
  let algunProductoNoExiste = false;

  const productos = [];
  for (const p of parsedInvoice.productos || []) {
    const existe = await existeEquivalencia(p.referencia, p.unidad);
    if (!existe) {
      todosProductosExisten = false;
      algunProductoNoExiste = true;
      errores.push(`Producto ${p.referencia} con unidad ${p.unidad} no tiene equivalencia`);
    }
    productos.push({ referencia: p.referencia, unidad: p.unidad, existeEquivalencia: existe });
  }

  let valido = false;
  let requiereHomologacion = false;
  if (proveedorExiste) {
    if (todosProductosExisten) valido = true;
    else if (algunProductoNoExiste) {
      valido = true;
      requiereHomologacion = true;
    }
  }

  return {
    ...(proveedorExiste ? { codigoTercero: proveedorInfo.codigo } : {}),
    valido,
    requiereHomologacion,
    proveedorExiste,
    productos,
    errores,
  };
};

module.exports = { validarDocumento };
