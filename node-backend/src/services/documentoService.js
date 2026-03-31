const fs = require('fs/promises');
const path = require('path');
const env = require('../config/env');
const { parseXmlFromFile } = require('./xmlService');
const { validarDocumento } = require('./validationService');
const eqRepo = require('../repositories/equivalenciaRepository');
const { documentoExiste, guardarDocumento } = require('../repositories/documentoRepository');
const { insertarOrdenCompra } = require('./helisaService');

const procesarDocumentos = async ({ files, session }) => {
  const procesados = [];
  const errores = [];

  for (const file of files || []) {
    const fileName = path.basename(file);
    const sourceFile = path.join(env.paths.inputDir, fileName);

    try {
      await fs.access(sourceFile);
    } catch {
      errores.push({ fileName, error: 'Archivo no encontrado' });
      continue;
    }

    if (await documentoExiste(fileName)) {
      errores.push({ fileName, error: 'El documento ya fue procesado anteriormente' });
      continue;
    }

    try {
      const parsed = await parseXmlFromFile(fileName);
      const validation = await validarDocumento({ proveedor: parsed.provider, productos: parsed.products, totales: parsed.totals });

      if (!(validation.valido && !validation.requiereHomologacion)) {
        errores.push({ fileName, error: validation.requiereHomologacion ? 'Requiere homologación de productos' : 'Documento inválido para procesar' });
        continue;
      }

      const detalles = [];
      for (const p of parsed.products) {
        const eqRows = await eqRepo.buscarEquivalencia(p.referencia, p.unidad);
        const eq = eqRows[0];
        const factor = eq ? Number(eq.FACTOR || 1) || 1 : 1;
        const cantidad = p.cantidad * factor;
        const precio = p.valorUnitario;
        detalles.push({
          codigoProducto: eq?.REFERENCIAH || p.referencia,
          codigoConcepto: Number(eq?.CODIGOH || 0),
          subcodigo: Number(eq?.SUBCODIGOH || 0),
          cantidad,
          precio,
          total: cantidad * precio,
          tfIva: p.impuestoPorcentaje,
          vrIva: p.impuesto,
          tfDescuento: p.descuentoPorcentaje,
          vrDescuento: p.descuento,
          vrIca: 0,
          vrReteIca: 0,
          vrReteIva: 0,
          vrReteFuente: 0,
          clase: 1,
          valorUnitario: precio,
          valorTotal: cantidad * precio,
        });
      }

      const header = {
        proveedor: parsed.provider.nit,
        codigoTercero: validation.codigoTercero,
        fecha: parsed.fechaEmision,
        total: parsed.totals.total,
        estado: 'PROCESADO',
        xmlFileName: fileName,
        nombreUsuario: session.nombre,
        codigoUsuario: String(session.codigo),
        anio: String(new Date(parsed.fechaEmision).getFullYear()),
      };

      const documentoERP = await guardarDocumento({
        header,
        detalles,
        insertarOrdenCompra: () => insertarOrdenCompra({ header, detalles }),
      });

      await fs.mkdir(env.paths.processedDir, { recursive: true });
      await fs.rename(sourceFile, path.join(env.paths.processedDir, fileName));
      procesados.push({ fileName, status: 'OK', documento: documentoERP });
    } catch (error) {
      errores.push({ fileName, error: `Error procesando archivo: ${error.message}` });
    }
  }

  return { procesados, errores };
};

module.exports = { procesarDocumentos };
