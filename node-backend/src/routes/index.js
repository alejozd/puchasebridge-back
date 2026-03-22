const express = require('express');
const auth = require('../controllers/authController');
const imp = require('../controllers/importController');
const prov = require('../controllers/proveedorController');
const xml = require('../controllers/xmlController');
const xmlVal = require('../controllers/xmlValidationController');
const eq = require('../controllers/equivalenciaController');
const helisa = require('../controllers/helisaController');
const docs = require('../controllers/documentosController');

const router = express.Router();

router.get('/ping', (req, res) => res.send('pong'));
router.post('/auth/login', auth.login);

router.post('/factura/xml', express.text({ type: '*/*' }), imp.postFacturaXml);
router.get('/proveedor/:nit', prov.getProveedor);

router.get('/xml/list', xml.list);
router.post('/xml/upload', xml.uploadMiddleware, xml.uploadXml);
router.post('/xml/parse', xml.parse);

router.post('/xml/validate', xmlVal.validate);
router.post('/xml/validate/batch', xmlVal.validateBatch);

router.get('/equivalencias', eq.list);
router.post('/equivalencia', eq.create);
router.delete('/equivalencia', eq.remove);

router.get('/helisa/productos', helisa.getProductos);
router.post('/documentos/procesar', docs.procesar);

module.exports = router;
