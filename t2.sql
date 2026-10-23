USE master;
GO
IF DB_ID(N'PlazaVea_G6_1000Productos_50Tiendas') IS NULL
    EXEC(N'CREATE DATABASE PlazaVea_G6_1000Productos_50Tiendas');
GO
USE PlazaVea_G6_1000Productos_50Tiendas;
GO
IF SCHEMA_ID(N'operacion') IS NULL EXEC(N'CREATE SCHEMA operacion');
GO
IF SCHEMA_ID(N'bi') IS NULL EXEC(N'CREATE SCHEMA bi');
GO
IF SCHEMA_ID(N'control') IS NULL EXEC(N'CREATE SCHEMA control');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* 1) Crear las 17 tablas desde cero, conservando claves y relaciones. */

/* Migracion: id_turno no es un dato de negocio; la venta queda relacionada
   directamente con el cajero, la tienda y la ventana horaria del turno. */
IF COL_LENGTH(N'operacion.Venta',N'id_turno') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'operacion.Venta',N'id_cajero') IS NULL
        ALTER TABLE operacion.Venta ADD id_cajero INT NULL;
    UPDATE v SET id_cajero=tu.id_cajero
    FROM operacion.Venta v JOIN operacion.Turno tu ON tu.id_turno=v.id_turno;
    IF EXISTS (SELECT 1 FROM operacion.Venta WHERE id_cajero IS NULL)
        THROW 52020,'No se pudo migrar alguna venta desde id_turno a id_cajero.',1;
    ALTER TABLE operacion.Venta ALTER COLUMN id_cajero INT NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Venta_Cajero')
        ALTER TABLE operacion.Venta ADD CONSTRAINT FK_Venta_Cajero
            FOREIGN KEY (id_cajero) REFERENCES operacion.Cajero(id_cajero);
    DECLARE @sql NVARCHAR(MAX)=N'';
    SELECT @sql=@sql+N'ALTER TABLE '+QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))+N'.'+
        QUOTENAME(OBJECT_NAME(parent_object_id))+N' DROP CONSTRAINT '+QUOTENAME(name)+N';'
    FROM sys.foreign_keys
    WHERE referenced_object_id=OBJECT_ID(N'operacion.Turno')
      AND parent_object_id=OBJECT_ID(N'operacion.Venta');
    IF @sql<>N'' EXEC sys.sp_executesql @sql;
    ALTER TABLE operacion.Venta DROP COLUMN id_turno;
END;
IF COL_LENGTH(N'operacion.Turno',N'id_turno') IS NOT NULL
BEGIN
    DECLARE @pk NVARCHAR(128);
    SELECT @pk=name FROM sys.key_constraints
    WHERE parent_object_id=OBJECT_ID(N'operacion.Turno') AND type=N'PK';
    IF @pk IS NOT NULL
    BEGIN
        SET @sql=N'ALTER TABLE operacion.Turno DROP CONSTRAINT '+QUOTENAME(@pk)+N';';
        EXEC sys.sp_executesql @sql;
    END;
    ALTER TABLE operacion.Turno DROP COLUMN id_turno;
END;

IF OBJECT_ID(N'operacion.Tienda',N'U') IS NULL
CREATE TABLE operacion.Tienda (
    id_tienda INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(100) NOT NULL,
    distrito NVARCHAR(80) NULL
);
IF OBJECT_ID(N'operacion.Producto',N'U') IS NULL
CREATE TABLE operacion.Producto (
    id_producto INT IDENTITY(1,1) PRIMARY KEY,
    codigo_barra VARCHAR(30) NOT NULL UNIQUE,
    nombre NVARCHAR(120) NOT NULL,
    marca NVARCHAR(80) NOT NULL CONSTRAINT DF_Producto_Marca DEFAULT N'Sin especificar',
    categoria NVARCHAR(70) NOT NULL,
    precio_actual DECIMAL(12,2) NOT NULL CHECK(precio_actual >= 0),
    activo BIT NOT NULL DEFAULT 1,
    CONSTRAINT UQ_Producto_NombreMarca UNIQUE(nombre, marca),
    CONSTRAINT UQ_Producto_Nombre UNIQUE(nombre)
);
IF OBJECT_ID(N'operacion.ClienteAnonimo',N'U') IS NULL
CREATE TABLE operacion.ClienteAnonimo (
    id_cliente BIGINT IDENTITY(1,1) PRIMARY KEY,
    dni CHAR(8) NOT NULL UNIQUE,
    fecha_alta DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'operacion.Cajero',N'U') IS NULL
CREATE TABLE operacion.Cajero (
    id_cajero INT IDENTITY(1,1) PRIMARY KEY,
    codigo_empleado VARCHAR(30) NOT NULL UNIQUE,
    nombres NVARCHAR(80) NOT NULL CONSTRAINT DF_Cajero_Nombres DEFAULT N'Sin asignar',
    apellidos NVARCHAR(100) NOT NULL CONSTRAINT DF_Cajero_Apellidos DEFAULT N'Sin asignar',
    activo BIT NOT NULL DEFAULT 1
);
IF OBJECT_ID(N'operacion.Turno',N'U') IS NULL
CREATE TABLE operacion.Turno (
    id_cajero INT NOT NULL REFERENCES operacion.Cajero(id_cajero),
    id_tienda INT NOT NULL REFERENCES operacion.Tienda(id_tienda),
    inicio DATETIME2 NOT NULL,
    fin DATETIME2 NULL,
    CONSTRAINT CK_Turno_Fechas CHECK (fin IS NULL OR fin > inicio)
);
IF OBJECT_ID(N'operacion.Venta',N'U') IS NULL
CREATE TABLE operacion.Venta (
    id_venta BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_evento_externo VARCHAR(70) NOT NULL UNIQUE,
    fecha_venta DATETIME2(0) NOT NULL,
    id_tienda INT NOT NULL REFERENCES operacion.Tienda(id_tienda),
    id_cliente BIGINT NULL REFERENCES operacion.ClienteAnonimo(id_cliente),
    id_cajero INT NOT NULL REFERENCES operacion.Cajero(id_cajero),
    canal VARCHAR(20) NOT NULL DEFAULT 'Tienda' CHECK(canal IN ('Tienda','Online')),
    metodo_pago VARCHAR(20) NOT NULL CHECK(metodo_pago IN ('Efectivo','Tarjeta','Billetera')),
    estado VARCHAR(20) NOT NULL DEFAULT 'Pagada' CHECK(estado IN ('Pagada','Anulada')),
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'operacion.DetalleVenta',N'U') IS NULL
CREATE TABLE operacion.DetalleVenta (
    id_detalle BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_venta BIGINT NOT NULL REFERENCES operacion.Venta(id_venta),
    id_producto INT NOT NULL REFERENCES operacion.Producto(id_producto),
    nro_linea SMALLINT NOT NULL CHECK(nro_linea > 0),
    cantidad INT NOT NULL CHECK(cantidad > 0),
    precio_unitario DECIMAL(12,2) NOT NULL CHECK(precio_unitario >= 0),
    importe AS (CONVERT(DECIMAL(15,2), cantidad * precio_unitario)) PERSISTED,
    CONSTRAINT UQ_Detalle_Linea UNIQUE (id_venta,nro_linea)
);
IF OBJECT_ID(N'operacion.Comprobante',N'U') IS NULL
CREATE TABLE operacion.Comprobante (
    id_comprobante BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_venta BIGINT NOT NULL UNIQUE REFERENCES operacion.Venta(id_venta),
    tipo VARCHAR(8) NOT NULL CHECK(tipo IN ('BOLETA','FACTURA')),
    serie VARCHAR(12) NOT NULL,
    numero BIGINT NOT NULL CHECK(numero > 0),
    estado_envio VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    CONSTRAINT UQ_Comprobante_SerieNumero UNIQUE (tipo,serie,numero)
);
IF OBJECT_ID(N'operacion.VisitaAgregada',N'U') IS NULL
CREATE TABLE operacion.VisitaAgregada (
    id_tienda INT NOT NULL REFERENCES operacion.Tienda(id_tienda),
    fecha DATE NOT NULL,
    visitas_totales INT NOT NULL CHECK(visitas_totales >= 0),
    fuente NVARCHAR(100) NOT NULL,
    PRIMARY KEY (id_tienda,fecha)
);
IF OBJECT_ID(N'bi.DimFecha',N'U') IS NULL
CREATE TABLE bi.DimFecha (
    fecha_key INT PRIMARY KEY,
    fecha DATE NOT NULL UNIQUE,
    anio SMALLINT NOT NULL, mes TINYINT NOT NULL, dia TINYINT NOT NULL
);
IF OBJECT_ID(N'bi.DimProducto',N'U') IS NULL
CREATE TABLE bi.DimProducto (
    producto_key INT IDENTITY(1,1) PRIMARY KEY,
    id_producto_oltp INT NOT NULL UNIQUE REFERENCES operacion.Producto(id_producto),
    nombre NVARCHAR(120) NOT NULL,
    marca NVARCHAR(80) NOT NULL CONSTRAINT DF_DimProducto_Marca DEFAULT N'Sin especificar',
    categoria NVARCHAR(70) NOT NULL,
    CONSTRAINT UQ_DimProducto_NombreMarca UNIQUE(nombre,marca),
    CONSTRAINT UQ_DimProducto_Nombre UNIQUE(nombre)
);
IF OBJECT_ID(N'bi.DimTienda',N'U') IS NULL
CREATE TABLE bi.DimTienda (
    tienda_key INT IDENTITY(1,1) PRIMARY KEY,
    id_tienda_oltp INT NOT NULL UNIQUE REFERENCES operacion.Tienda(id_tienda),
    nombre NVARCHAR(100) NOT NULL,
    distrito NVARCHAR(80) NULL
);
IF OBJECT_ID(N'bi.DimCliente',N'U') IS NULL
CREATE TABLE bi.DimCliente (
    cliente_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_cliente_oltp BIGINT NOT NULL UNIQUE REFERENCES operacion.ClienteAnonimo(id_cliente),
    dni CHAR(8) NULL,
    nombres NVARCHAR(80) NULL,
    apellidos NVARCHAR(100) NULL,
    segmento VARCHAR(20) NOT NULL DEFAULT 'Sin clasificar',
    CONSTRAINT UQ_DimCliente_Apellidos UNIQUE(apellidos)
);
/* La dimension de empleados no existia en el esquema original. */
IF OBJECT_ID(N'bi.DimEmpleado',N'U') IS NULL
CREATE TABLE bi.DimEmpleado (
    empleado_key INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_cajero_oltp INT NOT NULL UNIQUE REFERENCES operacion.Cajero(id_cajero),
    codigo_empleado VARCHAR(30) NOT NULL,
    nombres NVARCHAR(80) NOT NULL,
    apellidos NVARCHAR(100) NOT NULL,
    activo BIT NOT NULL,
    CONSTRAINT UQ_DimEmpleado_Apellidos UNIQUE(apellidos)
);
IF OBJECT_ID(N'bi.FactDetalleVenta',N'U') IS NULL
CREATE TABLE bi.FactDetalleVenta (
    id_detalle_oltp BIGINT NOT NULL PRIMARY KEY,
    fecha_key INT NOT NULL REFERENCES bi.DimFecha(fecha_key),
    producto_key INT NOT NULL REFERENCES bi.DimProducto(producto_key),
    tienda_key INT NOT NULL REFERENCES bi.DimTienda(tienda_key),
    cliente_key BIGINT NULL REFERENCES bi.DimCliente(cliente_key),
    id_venta BIGINT NOT NULL REFERENCES operacion.Venta(id_venta), cantidad INT NOT NULL,
    importe DECIMAL(15,2) NOT NULL,
    fecha_carga DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'bi.FactVisitaDiaria',N'U') IS NULL
CREATE TABLE bi.FactVisitaDiaria (
    fecha_key INT NOT NULL REFERENCES bi.DimFecha(fecha_key),
    tienda_key INT NOT NULL REFERENCES bi.DimTienda(tienda_key),
    visitas_totales INT NOT NULL,
    PRIMARY KEY (fecha_key,tienda_key)
);
IF OBJECT_ID(N'control.Watermark',N'U') IS NULL
CREATE TABLE control.Watermark (
    proceso VARCHAR(60) PRIMARY KEY,
    ultima_clave BIGINT NOT NULL DEFAULT 0,
    ultima_ejecucion DATETIME2 NULL
);


GO

/* 2) Poblar tablas, dimensionar y verificar dentro de una transaccion. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRY
    BEGIN TRANSACTION;
    /* Si el script ya se cargo antes, NO tocar datos existentes. */
    IF EXISTS (SELECT 1 FROM operacion.Producto)
       OR EXISTS (SELECT 1 FROM operacion.ClienteAnonimo)
       OR EXISTS (SELECT 1 FROM operacion.Venta)
       OR EXISTS (SELECT 1 FROM bi.DimProducto)
       THROW 52000,'La base de destino ya contiene datos: se cancela la carga sin modificarlos.',1;

    /* Números del 1 al 5000. */
    CREATE TABLE #N (n INT NOT NULL PRIMARY KEY);
    ;WITH D AS (SELECT d FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) v(d)),
    Numeros AS (
        SELECT ROW_NUMBER() OVER (ORDER BY d4.d,d3.d,d2.d,d1.d) n
        FROM D d1 CROSS JOIN D d2 CROSS JOIN D d3 CROSS JOIN D d4
    )
    INSERT INTO #N(n) SELECT TOP (5000) CONVERT(INT,n) FROM Numeros ORDER BY n;

    /* 3) Nombres y apellidos ficticios, aleatorios, sin repetir combinaciones. */
    CREATE TABLE #Nombre (id INT PRIMARY KEY,nombre NVARCHAR(80) NOT NULL);
    INSERT INTO #Nombre VALUES
    (1,N'Juan Carlos'),(2,N'María Fernanda'),(3,N'Luis Alberto'),(4,N'Ana Lucía'),
    (5,N'José Antonio'),(6,N'Valeria'),(7,N'Carlos Eduardo'),(8,N'Daniela'),
    (9,N'Miguel Ángel'),(10,N'Camila'),(11,N'Jorge Luis'),(12,N'Andrea'),
    (13,N'Pedro José'),(14,N'Luciana'),(15,N'Diego Alejandro'),(16,N'Gabriela'),
    (17,N'Fernando'),(18,N'Rosa María'),(19,N'Ricardo'),(20,N'Paola'),
    (21,N'Sebastián'),(22,N'Fiorella'),(23,N'Víctor Manuel'),(24,N'Natalia'),
    (25,N'Andrés'),(26,N'Claudia'),(27,N'Óscar'),(28,N'Adriana'),
    (29,N'Alexander'),(30,N'Patricia'),(31,N'Marco Antonio'),(32,N'Karla'),
    (33,N'Bryan'),(34,N'Elizabeth'),(35,N'Enrique'),(36,N'Fernanda'),
    (37,N'Ángel'),(38,N'Milagros'),(39,N'Hugo'),(40,N'Cristina');
    CREATE TABLE #Apellido(id INT PRIMARY KEY,apellido NVARCHAR(50) NOT NULL);
    INSERT INTO #Apellido VALUES
    (1,N'García'),(2,N'Flores'),(3,N'Quispe'),(4,N'Rojas'),(5,N'Gonzales'),
    (6,N'Ramírez'),(7,N'Mendoza'),(8,N'Torres'),(9,N'Vargas'),(10,N'Castillo'),
    (11,N'Pérez'),(12,N'Sánchez'),(13,N'Fernández'),(14,N'Huamaní'),(15,N'Chávez'),
    (16,N'Díaz'),(17,N'Rodríguez'),(18,N'Romero'),(19,N'Ruiz'),(20,N'Vega'),
    (21,N'Gutiérrez'),(22,N'Paredes'),(23,N'Aguilar'),(24,N'Medina'),(25,N'Valdez'),
    (26,N'Cruz'),(27,N'Salazar'),(28,N'Huerta'),(29,N'Navarro'),(30,N'Ortiz'),
    (31,N'Ramos'),(32,N'Cárdenas'),(33,N'Espinoza'),(34,N'Campos'),(35,N'Reyes'),
    (36,N'Aquino'),(37,N'Soto'),(38,N'Mamani'),(39,N'Zambrano'),(40,N'Palomino'),
    (41,N'Alarcón'),(42,N'Alvarado'),(43,N'Álvarez'),(44,N'Arce'),(45,N'Arévalo'),
    (46,N'Ávila'),(47,N'Bautista'),(48,N'Benavides'),(49,N'Blanco'),(50,N'Bravo'),
    (51,N'Cabrera'),(52,N'Cáceres'),(53,N'Calderón'),(54,N'Carrasco'),(55,N'Carrillo'),
    (56,N'Carvajal'),(57,N'Castro'),(58,N'Córdova'),(59,N'Cornejo'),(60,N'Cortés'),
    (61,N'Cuadros'),(62,N'Delgado'),(63,N'Domínguez'),(64,N'Escobar'),(65,N'Espino'),
    (66,N'Esquivel'),(67,N'Estrella'),(68,N'Farfán'),(69,N'Figueroa'),(70,N'Franco'),
    (71,N'Fuentes'),(72,N'Gálvez'),(73,N'Guerra'),(74,N'Guerrero'),(75,N'Guzmán'),
    (76,N'Hernández'),(77,N'Herrera'),(78,N'Hidalgo'),(79,N'Ibarra'),(80,N'Jiménez'),
    (81,N'Lagos'),(82,N'Lara'),(83,N'León'),(84,N'Loayza'),(85,N'Lozano'),
    (86,N'Luna'),(87,N'Maldonado'),(88,N'Marín'),(89,N'Martínez'),(90,N'Matos'),
    (91,N'Mejía'),(92,N'Meléndez'),(93,N'Meneses'),(94,N'Miranda'),(95,N'Montero'),
    (96,N'Mora'),(97,N'Morales'),(98,N'Muñoz'),(99,N'Nieto'),(100,N'Núñez'),
    (101,N'Ochoa'),(102,N'Olivares'),(103,N'Oré'),(104,N'Pacheco'),(105,N'Padilla'),
    (106,N'Palacios'),(107,N'Paz'),(108,N'Peña'),(109,N'Pineda'),(110,N'Ponce'),
    (111,N'Portilla'),(112,N'Prado'),(113,N'Puma'),(114,N'Quiroz'),(115,N'Reátegui'),
    (116,N'Robles'),(117,N'Roque'),(118,N'Rubio'),(119,N'Saavedra'),(120,N'Salas'),
    (121,N'Salinas'),(122,N'Sandoval'),(123,N'Santillán'),(124,N'Serna'),(125,N'Silva'),
    (126,N'Solis'),(127,N'Suárez'),(128,N'Tapia'),(129,N'Tejada'),(130,N'Tello'),
    (131,N'Toledo'),(132,N'Trujillo'),(133,N'Ugarte'),(134,N'Uribe'),(135,N'Valdivia'),
    (136,N'Valencia'),(137,N'Velásquez'),(138,N'Vera'),(139,N'Vidal'),(140,N'Villanueva'),
    (141,N'Yupanqui'),(142,N'Zapata'),(143,N'Zegarra');

    CREATE TABLE #ApellidosUnicos (
        n INT NOT NULL PRIMARY KEY,
        apellidos NVARCHAR(100) NOT NULL UNIQUE
    );
    ;WITH Mezcla AS (
        SELECT ROW_NUMBER() OVER (ORDER BY NEWID()) AS n,
               CONCAT(a.apellido,N' ',b.apellido) AS apellidos
        FROM #Apellido a CROSS JOIN #Apellido b
        WHERE a.id<>b.id
    )
    INSERT INTO #ApellidosUnicos(n,apellidos)
    SELECT CONVERT(INT,n),apellidos FROM Mezcla;

    IF (SELECT COUNT(*) FROM #ApellidosUnicos)<10000
       THROW 52001,'No hay suficientes apellidos unicos para 5000 clientes y 5000 empleados.',1;

    /* 4) CATALOGO ACADEMICO: 1000 SKUs DIFERENTES, SIN REPETIR NOMBRES.
           40 productos base se conservan y se amplian con 960 variantes
           diferenciadas por tipo, sabor, peso o presentacion.
           Marcas y precios son ilustrativos, NO inventario oficial de Plaza Vea. */
    CREATE TABLE #TipoProducto (
        id INT PRIMARY KEY,
        nombre NVARCHAR(95) NOT NULL,
        marca NVARCHAR(80) NOT NULL,
        categoria NVARCHAR(70) NOT NULL,
        precio DECIMAL(12,2) NULL
    );
    INSERT INTO #TipoProducto(id,nombre,marca,categoria) VALUES
    (1,N'Leche evaporada entera 400 g',N'Gloria',N'Lácteos'),
    (2,N'Yogur de fresa 1 L',N'Gloria',N'Lácteos'),
    (3,N'Leche deslactosada 1 L',N'Laive',N'Lácteos'),
    (4,N'Queso fresco 500 g',N'Laive',N'Lácteos'),
    (5,N'Leche condensada 393 g',N'Nestlé',N'Abarrotes'),
    (6,N'Cereal integral 450 g',N'Fitness',N'Abarrotes'),
    (7,N'Pan de molde integral 600 g',N'Bimbo',N'Panadería'),
    (8,N'Helado de vainilla 1 L',N'Donofrio',N'Congelados'),
    (9,N'Gaseosa cola 1.5 L',N'Coca-Cola',N'Bebidas'),
    (10,N'Gaseosa sabor original 1.5 L',N'Inca Kola',N'Bebidas'),
    (11,N'Agua sin gas 625 ml',N'San Luis',N'Bebidas'),
    (12,N'Agua sin gas 2.5 L',N'Cielo',N'Bebidas'),
    (13,N'Mayonesa 475 g',N'AlaCena',N'Abarrotes'),
    (14,N'Aceite vegetal 900 ml',N'Primor',N'Abarrotes'),
    (15,N'Arroz extra 5 kg',N'Costeño',N'Abarrotes'),
    (16,N'Fideos espagueti 500 g',N'Molitalia',N'Abarrotes'),
    (17,N'Fideos tornillo 500 g',N'Don Vittorio',N'Abarrotes'),
    (18,N'Galletas de soda 200 g',N'San Jorge',N'Abarrotes'),
    (19,N'Galletas de vainilla 150 g',N'Field',N'Abarrotes'),
    (20,N'Cacao en polvo 200 g',N'Winter''s',N'Abarrotes'),
    (21,N'Café instantáneo 200 g',N'Nescafé',N'Bebidas'),
    (22,N'Café molido 250 g',N'Altomayo',N'Bebidas'),
    (23,N'Jabón para ropa 210 g',N'Bolívar',N'Limpieza'),
    (24,N'Detergente en polvo 2 kg',N'Ariel',N'Limpieza'),
    (25,N'Detergente en polvo 900 g',N'Ace',N'Limpieza'),
    (26,N'Lavavajillas líquido 750 ml',N'Sapolio',N'Limpieza'),
    (27,N'Lavavajillas en pasta 450 g',N'Ayudín',N'Limpieza'),
    (28,N'Papel higiénico 12 rollos',N'Elite',N'Limpieza'),
    (29,N'Papel higiénico 4 rollos',N'Suave',N'Limpieza'),
    (30,N'Pasta dental 90 g',N'Colgate',N'Cuidado personal'),
    (31,N'Champú anticaspa 375 ml',N'Head & Shoulders',N'Cuidado personal'),
    (32,N'Acondicionador 400 ml',N'Pantene',N'Cuidado personal'),
    (33,N'Máquina de afeitar 2 unidades',N'Gillette',N'Cuidado personal'),
    (34,N'Crema corporal 400 ml',N'Nivea',N'Cuidado personal'),
    (35,N'Cubitos de caldo 12 unidades',N'Knorr',N'Abarrotes'),
    (36,N'Ají panca molido 100 g',N'Sibarita',N'Abarrotes'),
    (37,N'Azúcar rubia 1 kg',N'Bell''s',N'Abarrotes'),
    (38,N'Atún en aceite 170 g',N'Florida',N'Conservas'),
    (39,N'Mermelada de fresa 320 g',N'Fanny',N'Abarrotes'),
    (40,N'Chocolate de leche 100 g',N'Sublime',N'Golosinas');

    UPDATE #TipoProducto SET precio=CASE id
        WHEN 1 THEN 5.20
        WHEN 2 THEN 8.50
        WHEN 3 THEN 7.90
        WHEN 4 THEN 17.90
        WHEN 5 THEN 8.90
        WHEN 6 THEN 18.90
        WHEN 7 THEN 12.50
        WHEN 8 THEN 16.90
        WHEN 9 THEN 8.90
        WHEN 10 THEN 8.70
        WHEN 11 THEN 2.50
        WHEN 12 THEN 6.50
        WHEN 13 THEN 10.20
        WHEN 14 THEN 10.90
        WHEN 15 THEN 26.00
        WHEN 16 THEN 5.50
        WHEN 17 THEN 5.70
        WHEN 18 THEN 4.90
        WHEN 19 THEN 4.20
        WHEN 20 THEN 12.50
        WHEN 21 THEN 20.50
        WHEN 22 THEN 22.80
        WHEN 23 THEN 3.90
        WHEN 24 THEN 22.00
        WHEN 25 THEN 11.50
        WHEN 26 THEN 8.90
        WHEN 27 THEN 8.20
        WHEN 28 THEN 19.50
        WHEN 29 THEN 8.50
        WHEN 30 THEN 11.70
        WHEN 31 THEN 23.60
        WHEN 32 THEN 21.50
        WHEN 33 THEN 17.50
        WHEN 34 THEN 23.80
        WHEN 35 THEN 8.50
        WHEN 36 THEN 5.90
        WHEN 37 THEN 5.40
        WHEN 38 THEN 9.60
        WHEN 39 THEN 9.20
        WHEN 40 THEN 7.80
        ELSE NULL END;

    /* 960 productos adicionales, todos distintos y con su propio precio. */
    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (41,N'Leche evaporada sin lactosa 400 g',N'Gloria',N'Lácteos',3.00),
      (42,N'Leche fresca semidescremada 2 L',N'Laive',N'Lácteos',11.50),
      (43,N'Leche fresca light 2 L',N'Gloria',N'Lácteos',11.50),
      (44,N'Yogur bebible frutos rojos 1 L',N'Gloria',N'Lácteos',9.90),
      (45,N'Yogur bebible natural 1.8 L',N'Laive',N'Lácteos',15.90),
      (46,N'Yogur griego vainilla 120 g',N'Danlac',N'Lácteos',4.10),
      (47,N'Queso fresco tradicional 500 g',N'Laive',N'Lácteos',10.30),
      (48,N'Queso mozzarella en tajadas 300 g',N'Bonlé',N'Lácteos',9.90),
      (49,N'Queso edam en tajadas 180 g',N'Laive',N'Lácteos',8.40),
      (50,N'Mantequilla light 200 g',N'Gloria',N'Lácteos',5.00),
      (51,N'Mantequilla con sal 100 g',N'Laive',N'Lácteos',5.40),
      (52,N'Crema de leche ligera 1 L',N'Nestlé',N'Lácteos',9.70),
      (53,N'Manjar blanco tradicional 200 g',N'Gloria',N'Lácteos',4.40),
      (54,N'Leche en polvo descremada 400 g',N'Gloria',N'Lácteos',12.10),
      (55,N'Leche condensada tradicional 850 g',N'Nestlé',N'Lácteos',8.30),
      (56,N'Arroz superior 5 kg',N'Costeño',N'Abarrotes',21.50),
      (57,N'Arroz integral 1 kg',N'Paisana',N'Abarrotes',13.00),
      (58,N'Azúcar extra fina 1 kg',N'Bell''s',N'Abarrotes',6.80),
      (59,N'Azúcar rubia 5 kg',N'Cartavio',N'Abarrotes',11.00),
      (60,N'Fideos coditos 500 g',N'Molitalia',N'Abarrotes',4.60),
      (61,N'Fideos pluma 250 g',N'Don Vittorio',N'Abarrotes',3.50),
      (62,N'Harina de trigo preparada 2 kg',N'Alianza',N'Abarrotes',10.30),
      (63,N'Harina sin preparar 2 kg',N'Blanca Flor',N'Abarrotes',11.90),
      (64,N'Aceite vegetal mezcla 500 ml',N'Primor',N'Abarrotes',8.10),
      (65,N'Aceite de girasol 250 ml',N'Cocinero',N'Abarrotes',8.30),
      (66,N'Mayonesa light 850 g',N'AlaCena',N'Abarrotes',11.70),
      (67,N'Kétchup sin azúcar 800 g',N'AlaCena',N'Abarrotes',10.60),
      (68,N'Mostaza picante 500 g',N'AlaCena',N'Abarrotes',5.40),
      (69,N'Sazonador para guisos 100 g',N'Maggi',N'Abarrotes',2.50),
      (70,N'Condimento molido pimienta 30 g',N'Sibarita',N'Abarrotes',5.70),
      (71,N'Cubitos de caldo carne 12 unidades',N'Knorr',N'Abarrotes',9.50),
      (72,N'Avena instantánea 1 kg',N'Quaker',N'Abarrotes',10.60),
      (73,N'Cereal chocolate 400 g',N'Nestlé',N'Abarrotes',12.90),
      (74,N'Cereal integral original 200 g',N'Fitness',N'Abarrotes',8.80),
      (75,N'Galletas saladas 150 g',N'San Jorge',N'Abarrotes',3.20),
      (76,N'Galletas vainilla 300 g',N'Field',N'Abarrotes',3.90),
      (77,N'Mermelada mora 320 g',N'Fanny',N'Abarrotes',10.40),
      (78,N'Mermelada durazno 500 g',N'Gloria',N'Abarrotes',7.40),
      (79,N'Cacao en polvo puro 400 g',N'Winter''s',N'Abarrotes',9.20),
      (80,N'Chocolate para taza con canela 360 g',N'Cocoa',N'Abarrotes',12.50),
      (81,N'Avena con maca 200 g',N'3 Ositos',N'Abarrotes',4.30),
      (82,N'Lentejas seleccionadas 2 kg',N'Costeño',N'Abarrotes',18.40),
      (83,N'Frejoles negro 1 kg',N'Costeño',N'Abarrotes',12.70),
      (84,N'Garbanzos extra 2 kg',N'Costeño',N'Abarrotes',22.00),
      (85,N'Sal de mesa marina 1 kg',N'Bell''s',N'Abarrotes',4.40),
      (86,N'Levadura instantánea 11 g',N'Fleischmann',N'Abarrotes',7.60),
      (87,N'Gelatina uva 80 g',N'Negrita',N'Abarrotes',2.50),
      (88,N'Pudín chocolate 100 g',N'Negrita',N'Abarrotes',3.00),
      (89,N'Vinagre blanco 500 ml',N'Bell''s',N'Abarrotes',5.00),
      (90,N'Salsa de soya oscura 300 ml',N'Bell''s',N'Abarrotes',5.30),
      (91,N'Ají en pasta panca 100 g',N'Uchucuta',N'Abarrotes',3.00),
      (92,N'Mantequilla de maní crujiente 400 g',N'Bimbo',N'Abarrotes',13.30),
      (93,N'Gaseosa cola sin azúcar 1 L',N'Coca-Cola',N'Bebidas',8.30),
      (94,N'Gaseosa sin azúcar 500 ml',N'Inca Kola',N'Bebidas',5.60),
      (95,N'Gaseosa limón sin azúcar 2.25 L',N'Sprite',N'Bebidas',12.80),
      (96,N'Gaseosa uva 1.5 L',N'Fanta',N'Bebidas',13.20),
      (97,N'Agua de mesa con gas 7 L',N'San Luis',N'Bebidas',7.80),
      (98,N'Agua de mesa sin gas 7 L',N'Cielo',N'Bebidas',7.30),
      (99,N'Néctar mix de frutas 1.5 L',N'Frugos',N'Bebidas',11.00),
      (100,N'Néctar manzana 1.5 L',N'Pulp',N'Bebidas',10.80),
      (101,N'Bebida rehidratante uva 1.5 L',N'Sporade',N'Bebidas',11.60),
      (102,N'Bebida isotónica uva 500 ml',N'Gatorade',N'Bebidas',6.00),
      (103,N'Bebida energética original 250 ml',N'Red Bull',N'Bebidas',5.30),
      (104,N'Bebida energética original 1 L',N'Volt',N'Bebidas',6.40),
      (105,N'Café soluble suave 100 g',N'Nescafé',N'Bebidas',8.80),
      (106,N'Café molido intenso 125 g',N'Altomayo',N'Bebidas',20.60),
      (107,N'Café tostado clásico 500 g',N'Cafetal',N'Bebidas',16.70),
      (108,N'Infusión anís 40 sobres',N'McColins',N'Bebidas',7.30),
      (109,N'Té verde 40 sobres',N'Hornimans',N'Bebidas',9.10),
      (110,N'Bebida chocolatada con avena 200 ml',N'Gloria',N'Bebidas',3.80),
      (111,N'Té helado durazno 1.5 L',N'Fuze Tea',N'Bebidas',10.30),
      (112,N'Bebida láctea vainilla 200 ml',N'Pura Vida',N'Bebidas',2.50),
      (113,N'Detergente en polvo con aroma floral 2 kg',N'Ariel',N'Limpieza',36.60),
      (114,N'Detergente en polvo limón 4 kg',N'Ace',N'Limpieza',31.50),
      (115,N'Jabón para ropa antibacterial 900 g',N'Bolívar',N'Limpieza',7.70),
      (116,N'Lavavajillas líquido naranja 500 ml',N'Sapolio',N'Limpieza',7.10),
      (117,N'Lavavajillas en pasta naranja 250 g',N'Ayudín',N'Limpieza',3.90),
      (118,N'Limpiador multiuso floral 900 ml',N'Poett',N'Limpieza',10.50),
      (119,N'Lejía aroma floral 1 L',N'Sapolio',N'Limpieza',7.70),
      (120,N'Lejía clásica 2 L',N'Clorox',N'Limpieza',13.60),
      (121,N'Limpiador de cocina desengrasante 1 L',N'Mr. Músculo',N'Limpieza',13.60),
      (122,N'Limpiador de baño desinfectante 500 ml',N'Harpic',N'Limpieza',8.90),
      (123,N'Papel higiénico doble hoja 24 rollos',N'Elite',N'Limpieza',29.80),
      (124,N'Papel higiénico triple hoja 4 rollos',N'Suave',N'Limpieza',20.10),
      (125,N'Papel toalla multiuso 4 rollos',N'Scott',N'Limpieza',15.20),
      (126,N'Servilletas de papel decoradas 100 unidades',N'Elite',N'Limpieza',4.10),
      (127,N'Suavizante de ropa frescura de algodón 400 ml',N'Downy',N'Limpieza',11.30),
      (128,N'Suavizante de ropa floral 800 ml',N'Suavitel',N'Limpieza',15.90),
      (129,N'Insecticida doméstico para mosquitos 360 ml',N'Raid',N'Limpieza',19.70),
      (130,N'Esponja de cocina suave 4 unidades',N'Sapolio',N'Limpieza',6.80),
      (131,N'Paños de limpieza absorbentes 4 unidades',N'Virutex',N'Limpieza',10.40),
      (132,N'Ambientador floral 270 ml',N'Glade',N'Limpieza',13.00),
      (133,N'Pasta dental triple acción 150 ml',N'Colgate',N'Cuidado personal',4.60),
      (134,N'Pasta dental protección total 100 ml',N'Oral-B',N'Cuidado personal',5.60),
      (135,N'Champú control grasa 180 ml',N'Head & Shoulders',N'Cuidado personal',10.80),
      (136,N'Champú reparación 200 ml',N'Pantene',N'Cuidado personal',10.30),
      (137,N'Acondicionador reparación 400 ml',N'Pantene',N'Cuidado personal',15.60),
      (138,N'Champú rizos 650 ml',N'Sedal',N'Cuidado personal',20.80),
      (139,N'Crema corporal hidratación intensiva 400 ml',N'Nivea',N'Cuidado personal',14.80),
      (140,N'Jabón de tocador humectante 360 g',N'Dove',N'Cuidado personal',8.60);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (141,N'Jabón de tocador aloe vera 180 g',N'Protex',N'Cuidado personal',3.70),
      (142,N'Desodorante antitranspirante 200 ml',N'Rexona',N'Cuidado personal',6.20),
      (143,N'Desodorante invisible 150 ml',N'Nivea',N'Cuidado personal',6.50),
      (144,N'Máquinas de afeitar 2 hojas 8 unidades',N'Gillette',N'Cuidado personal',26.00),
      (145,N'Espuma de afeitar clásica 400 ml',N'Gillette',N'Cuidado personal',13.00),
      (146,N'Toallas higiénicas ultradelgada 8 unidades',N'Kotex',N'Cuidado personal',15.80),
      (147,N'Cepillo dental medio 1 unidad',N'Oral-B',N'Cuidado personal',9.20),
      (148,N'Enjuague bucal sin alcohol 500 ml',N'Listerine',N'Cuidado personal',13.90),
      (149,N'Algodón discos 50 g',N'Johnson’s',N'Cuidado personal',3.10),
      (150,N'Protector solar FPS 50 200 ml',N'Nivea',N'Cuidado personal',17.70),
      (151,N'Crema para manos aloe vera 300 ml',N'Dove',N'Cuidado personal',9.90),
      (152,N'Helado fresa 500 ml',N'D’Onofrio',N'Congelados',13.20),
      (153,N'Helado chocolate 1 L',N'Artika',N'Congelados',18.10),
      (154,N'Nuggets de pollo crocanes 500 g',N'San Fernando',N'Congelados',15.90),
      (155,N'Hamburguesas congeladas parrilleras 8 unidades',N'Braedt',N'Congelados',34.80),
      (156,N'Papas prefritas corte fino 1 kg',N'McCain',N'Congelados',19.50),
      (157,N'Verduras congeladas zanahoria y arveja 400 g',N'Bell’s',N'Congelados',8.50),
      (158,N'Frutas congeladas fresa 300 g',N'Bell’s',N'Congelados',12.30),
      (159,N'Milanesa de pollo congelada clásica 800 g',N'San Fernando',N'Congelados',32.00),
      (160,N'Paletas heladas vainilla 6 unidades',N'D’Onofrio',N'Congelados',13.60),
      (161,N'Pizza congelada mozzarella 750 g',N'Bell’s',N'Congelados',23.80),
      (162,N'Atún en conserva salsa de tomate 300 g',N'Florida',N'Conservas',6.90),
      (163,N'Atún en conserva aceite 170 g',N'Campomar',N'Conservas',4.80),
      (164,N'Sardinas en conserva aceite 170 g',N'Gloria',N'Conservas',4.20),
      (165,N'Choclo en conserva grano entero 200 g',N'Bell’s',N'Conservas',4.00),
      (166,N'Arvejas en conserva verdes 200 g',N'Bell’s',N'Conservas',4.00),
      (167,N'Duraznos en almíbar light 420 g',N'Bell’s',N'Conservas',8.40),
      (168,N'Piña en almíbar en rodajas 820 g',N'Bell’s',N'Conservas',12.60),
      (169,N'Pasta de tomate condimentada 400 g',N'Del Monte',N'Conservas',5.10),
      (170,N'Aceitunas verdes 500 g',N'Bell’s',N'Conservas',8.40),
      (171,N'Palmitos en conserva enteros 200 g',N'Bell’s',N'Conservas',7.80),
      (172,N'Pan de molde multigrano 600 g',N'Bimbo',N'Panadería',13.30),
      (173,N'Pan para hamburguesa con ajonjolí 8 unidades',N'Bimbo',N'Panadería',13.30),
      (174,N'Pan para hot dog integral 4 unidades',N'Bimbo',N'Panadería',8.60),
      (175,N'Pan artesanal masa madre 800 g',N'Pan de la Chola',N'Panadería',19.70),
      (176,N'Tostadas clásicas 300 g',N'Bell’s',N'Panadería',5.40),
      (177,N'Galletas de agua saladas 200 g',N'San Jorge',N'Panadería',3.10),
      (178,N'Queque marmoleado 250 g',N'Bimbo',N'Panadería',6.30),
      (179,N'Tortillas para wraps trigo 10 unidades',N'Bell’s',N'Panadería',14.40),
      (180,N'Panetón clásico 500 g',N'Bimbo',N'Panadería',14.60),
      (181,N'Rosquitas de mantequilla 300 g',N'Bell’s',N'Panadería',5.60),
      (182,N'Chocolate leche 100 g',N'Sublime',N'Golosinas',2.90),
      (183,N'Chocolate blanco 35 g',N'Nestlé',N'Golosinas',8.90),
      (184,N'Grageas de chocolate chocolate crocante 45 g',N'M&M’s',N'Golosinas',9.60),
      (185,N'Gomitas frutas 100 g',N'Haribo',N'Golosinas',4.10),
      (186,N'Chicle fresa 5 unidades',N'Trident',N'Golosinas',5.70),
      (187,N'Caramelos cereza 5 unidades',N'Halls',N'Golosinas',5.20),
      (188,N'Caramelos masticables frutales 100 g',N'Ambrosoli',N'Golosinas',3.40),
      (189,N'Wafers maní 60 g',N'Field',N'Golosinas',2.50),
      (190,N'Papas fritas clásicas 80 g',N'Lay’s',N'Golosinas',3.10),
      (191,N'Nachos barbacoa 45 g',N'Doritos',N'Golosinas',7.50),
      (192,N'Alimento seco para perros razas pequeñas 1 kg',N'Ricocan',N'Mascotas',41.00),
      (193,N'Alimento seco para perros carne 1 kg',N'Pedigree',N'Mascotas',42.90),
      (194,N'Alimento seco para gatos esterilizados 3 kg',N'Ricocat',N'Mascotas',54.80),
      (195,N'Alimento seco para gatos gatitos 1 kg',N'Whiskas',N'Mascotas',38.50),
      (196,N'Alimento húmedo para perros pollo 500 g',N'Dog Chow',N'Mascotas',5.50),
      (197,N'Alimento húmedo para gatos pollo 340 g',N'Felix',N'Mascotas',7.40),
      (198,N'Arena sanitaria para gatos clásica 5 kg',N'Cat’s Best',N'Mascotas',50.60),
      (199,N'Snacks para perros pollo 150 g',N'Ricocan',N'Mascotas',5.40),
      (200,N'Snacks para gatos salmón 180 g',N'Ricocat',N'Mascotas',4.80),
      (201,N'Champú para mascotas piel sensible 500 ml',N'Hartz',N'Mascotas',16.00),
      (202,N'Pañales talla M 60 unidades',N'Huggies',N'Bebés',62.40),
      (203,N'Pañales talla P 60 unidades',N'Pampers',N'Bebés',66.80),
      (204,N'Champú para bebé manzanilla 750 ml',N'Johnson’s',N'Bebés',22.80),
      (205,N'Jabón para bebé clásico 360 g',N'Johnson’s',N'Bebés',9.60),
      (206,N'Toallitas húmedas aloe vera 120 unidades',N'Pigeon',N'Bebés',14.40),
      (207,N'Toallitas húmedas aloe vera 40 unidades',N'Huggies',N'Bebés',16.60),
      (208,N'Compota para bebé manzana 200 g',N'Gerber',N'Bebés',3.70),
      (209,N'Cereal para bebé arroz 100 g',N'Nestlé',N'Bebés',5.10),
      (210,N'Crema para bebé hidratante 400 ml',N'Johnson’s',N'Bebés',12.40),
      (211,N'Pañales tipo calzón talla G 32 unidades',N'Huggies',N'Bebés',45.80),
      (212,N'Manzana empacada fuji 500 g',N'Fresco',N'Frutas y verduras',6.80),
      (213,N'Pera empacada abate 2 kg',N'Fresco',N'Frutas y verduras',17.00),
      (214,N'Uva empacada verde 1 kg',N'Fresco',N'Frutas y verduras',13.00),
      (215,N'Mandarina empacada satsuma 500 g',N'Fresco',N'Frutas y verduras',6.00),
      (216,N'Naranja empacada valencia 2 kg',N'Fresco',N'Frutas y verduras',11.90),
      (217,N'Plátano empacado de seda 1 kg',N'Fresco',N'Frutas y verduras',7.40),
      (218,N'Tomate empacado cherry 1 kg',N'Fresco',N'Frutas y verduras',8.90),
      (219,N'Papa empacada blanca 2 kg',N'Fresco',N'Frutas y verduras',12.20),
      (220,N'Cebolla empacada blanca 1 kg',N'Fresco',N'Frutas y verduras',7.60),
      (221,N'Lechuga empacada romana 3 unidades',N'Fresco',N'Frutas y verduras',6.20),
      (222,N'Zanahoria empacada baby 500 g',N'Fresco',N'Frutas y verduras',5.10),
      (223,N'Palta empacada fuerte 500 g',N'Fresco',N'Frutas y verduras',8.40),
      (224,N'Pechuga de pollo fileteada 500 g',N'San Fernando',N'Carnes y embutidos',12.90),
      (225,N'Pierna de pollo marinada 500 g',N'San Fernando',N'Carnes y embutidos',9.70),
      (226,N'Carne molida res magra 500 g',N'Redondos',N'Carnes y embutidos',16.20),
      (227,N'Bistec de res lomo fino 500 g',N'Redondos',N'Carnes y embutidos',23.60),
      (228,N'Jamón de pavo clásico 500 g',N'San Fernando',N'Carnes y embutidos',10.60),
      (229,N'Jamón inglés ahumado 250 g',N'Braedt',N'Carnes y embutidos',7.50),
      (230,N'Salchicha de pavo 1 kg',N'Braedt',N'Carnes y embutidos',13.90),
      (231,N'Chorizo picante 1 kg',N'San Fernando',N'Carnes y embutidos',18.10),
      (232,N'Salame clásico 250 g',N'Otto Kunz',N'Carnes y embutidos',8.20),
      (233,N'Tocino clásico 500 g',N'Braedt',N'Carnes y embutidos',12.10),
      (234,N'Papel aluminio estándar 20 m',N'Reynolds',N'Hogar',16.30),
      (235,N'Film plástico extra ancho 60 m',N'Alpesa',N'Hogar',6.60),
      (236,N'Bolsas para basura pequeñas 20 unidades',N'Duraplast',N'Hogar',10.60),
      (237,N'Bolsas herméticas grandes 10 unidades',N'Ziploc',N'Hogar',17.90),
      (238,N'Pañuelos faciales premium 200 unidades',N'Kleenex',N'Hogar',4.90),
      (239,N'Velas aromáticas lavanda 4 unidades',N'Glade',N'Hogar',14.90),
      (240,N'Encendedores largos 1 unidad',N'Bic',N'Hogar',8.00);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (241,N'Pilas alcalinas AAA 8 unidades',N'Varta',N'Hogar',17.60),
      (242,N'Esponja de cocina antiadherente 4 unidades',N'Tramontina',N'Hogar',7.80),
      (243,N'Guantes de limpieza talla L 3 pares',N'Scotch-Brite',N'Hogar',11.80),
      (244,N'Barra de cereal frutos rojos 25 g',N'Cerevita',N'Bienestar',5.20),
      (245,N'Barra de granola almendras 80 g',N'Nature Valley',N'Bienestar',3.70),
      (246,N'Galletas de avena pasas 240 g',N'Quaker',N'Bienestar',7.60),
      (247,N'Frutos secos mix 200 g',N'Bell’s',N'Bienestar',8.60),
      (248,N'Semillas chía 100 g',N'Bell’s',N'Bienestar',6.30),
      (249,N'Mantequilla de almendras sin azúcar 350 g',N'Bell’s',N'Bienestar',18.00),
      (250,N'Mix de frutos secos con arándanos 200 g',N'Granuts',N'Bienestar',8.60),
      (251,N'Quinua tricolor 500 g',N'Bell’s',N'Bienestar',8.40),
      (252,N'Kiwicha tradicional 500 g',N'Bell’s',N'Bienestar',7.90),
      (253,N'Miel de abeja de eucalipto 750 g',N'Bell’s',N'Bienestar',22.70),
      (254,N'Leche evaporada light 900 g',N'Gloria',N'Lácteos',5.60),
      (255,N'Leche fresca sin lactosa 250 ml',N'Laive',N'Lácteos',3.20),
      (256,N'Leche fresca entera 250 ml',N'Gloria',N'Lácteos',3.40),
      (257,N'Yogur bebible durazno 200 ml',N'Gloria',N'Lácteos',4.40),
      (258,N'Yogur bebible natural 900 ml',N'Laive',N'Lácteos',9.80),
      (259,N'Yogur griego fresa 500 g',N'Danlac',N'Lácteos',5.50),
      (260,N'Queso fresco bajo en sal 200 g',N'Laive',N'Lácteos',5.90),
      (261,N'Queso mozzarella en bloque 300 g',N'Bonlé',N'Lácteos',10.50),
      (262,N'Queso edam en tajadas 350 g',N'Laive',N'Lácteos',14.20),
      (263,N'Mantequilla light 400 g',N'Gloria',N'Lácteos',8.70),
      (264,N'Mantequilla sin sal 200 g',N'Laive',N'Lácteos',6.00),
      (265,N'Crema de leche clásica 200 ml',N'Nestlé',N'Lácteos',3.20),
      (266,N'Manjar blanco light 200 g',N'Gloria',N'Lácteos',3.70),
      (267,N'Leche en polvo instantánea 400 g',N'Gloria',N'Lácteos',11.30),
      (268,N'Leche condensada light 850 g',N'Nestlé',N'Lácteos',8.90),
      (269,N'Arroz añejo 1 kg',N'Costeño',N'Abarrotes',14.60),
      (270,N'Arroz superior 1 kg',N'Paisana',N'Abarrotes',13.60),
      (271,N'Azúcar rubia 2 kg',N'Cartavio',N'Abarrotes',11.40),
      (272,N'Fideos tornillo 250 g',N'Molitalia',N'Abarrotes',2.50),
      (273,N'Fideos lasagna 1 kg',N'Don Vittorio',N'Abarrotes',7.10),
      (274,N'Harina de trigo sin preparar 1 kg',N'Alianza',N'Abarrotes',6.90),
      (275,N'Harina preparada 1 kg',N'Blanca Flor',N'Abarrotes',8.00),
      (276,N'Aceite vegetal de soya 3 L',N'Primor',N'Abarrotes',20.30),
      (277,N'Aceite de soya 1 L',N'Cocinero',N'Abarrotes',21.70),
      (278,N'Mayonesa con limón 100 g',N'AlaCena',N'Abarrotes',5.70),
      (279,N'Kétchup picante 100 g',N'AlaCena',N'Abarrotes',3.40),
      (280,N'Mostaza dulce 250 g',N'AlaCena',N'Abarrotes',2.60),
      (281,N'Sazonador para arroz 200 g',N'Maggi',N'Abarrotes',2.50),
      (282,N'Condimento molido pimienta 250 g',N'Sibarita',N'Abarrotes',2.70),
      (283,N'Cubitos de caldo verduras 6 unidades',N'Knorr',N'Abarrotes',7.10),
      (284,N'Avena con quinua 500 g',N'Quaker',N'Abarrotes',7.00),
      (285,N'Cereal miel 700 g',N'Nestlé',N'Abarrotes',20.80),
      (286,N'Cereal integral frutos rojos 700 g',N'Fitness',N'Abarrotes',20.80),
      (287,N'Galletas vainilla 200 g',N'San Jorge',N'Abarrotes',2.50),
      (288,N'Galletas limón 70 g',N'Field',N'Abarrotes',2.60),
      (289,N'Mermelada mora 500 g',N'Fanny',N'Abarrotes',7.80),
      (290,N'Mermelada fresa 200 g',N'Gloria',N'Abarrotes',5.00),
      (291,N'Cacao en polvo instantáneo 100 g',N'Winter''s',N'Abarrotes',6.10),
      (292,N'Chocolate para taza amargo 360 g',N'Cocoa',N'Abarrotes',12.90),
      (293,N'Avena integral 900 g',N'3 Ositos',N'Abarrotes',9.40),
      (294,N'Lentejas seleccionadas 500 g',N'Costeño',N'Abarrotes',7.00),
      (295,N'Frejoles panamito 2 kg',N'Costeño',N'Abarrotes',19.90),
      (296,N'Garbanzos extra 500 g',N'Costeño',N'Abarrotes',9.20),
      (297,N'Sal de mesa gruesa 2 kg',N'Bell''s',N'Abarrotes',7.20),
      (298,N'Levadura instantánea 50 g',N'Fleischmann',N'Abarrotes',3.80),
      (299,N'Gelatina fresa 80 g',N'Negrita',N'Abarrotes',2.80),
      (300,N'Pudín caramelo 200 g',N'Negrita',N'Abarrotes',2.50),
      (301,N'Vinagre de manzana 1 L',N'Bell''s',N'Abarrotes',6.60),
      (302,N'Salsa de soya baja en sodio 300 ml',N'Bell''s',N'Abarrotes',5.60),
      (303,N'Ají en pasta amarillo 200 g',N'Uchucuta',N'Abarrotes',3.40),
      (304,N'Mantequilla de maní cremosa 750 g',N'Bimbo',N'Abarrotes',21.80),
      (305,N'Gaseosa cola original 1 L',N'Coca-Cola',N'Bebidas',8.70),
      (306,N'Gaseosa sin azúcar 1 L',N'Inca Kola',N'Bebidas',9.20),
      (307,N'Gaseosa limón original 500 ml',N'Sprite',N'Bebidas',4.50),
      (308,N'Gaseosa naranja 500 ml',N'Fanta',N'Bebidas',4.80),
      (309,N'Agua de mesa con gas 625 ml',N'San Luis',N'Bebidas',5.30),
      (310,N'Agua de mesa sin gas 1 L',N'Cielo',N'Bebidas',5.10),
      (311,N'Néctar mix de frutas 1 L',N'Frugos',N'Bebidas',7.60),
      (312,N'Néctar naranja 1.5 L',N'Pulp',N'Bebidas',11.20),
      (313,N'Bebida rehidratante tropical 1.5 L',N'Sporade',N'Bebidas',11.90),
      (314,N'Bebida isotónica frutos rojos 750 ml',N'Gatorade',N'Bebidas',8.40),
      (315,N'Bebida energética sin azúcar 473 ml',N'Red Bull',N'Bebidas',7.20),
      (316,N'Bebida energética frutos rojos 1 L',N'Volt',N'Bebidas',6.80),
      (317,N'Café soluble intenso 200 g',N'Nescafé',N'Bebidas',9.20),
      (318,N'Café molido orgánico 125 g',N'Altomayo',N'Bebidas',21.00),
      (319,N'Café tostado extra fuerte 125 g',N'Cafetal',N'Bebidas',23.60),
      (320,N'Infusión hierba luisa 20 sobres',N'McColins',N'Bebidas',7.30),
      (321,N'Té negro 40 sobres',N'Hornimans',N'Bebidas',8.10),
      (322,N'Bebida chocolatada con avena 1 L',N'Gloria',N'Bebidas',7.80),
      (323,N'Té helado limón 500 ml',N'Fuze Tea',N'Bebidas',4.30),
      (324,N'Bebida láctea fresa 1.5 L',N'Pura Vida',N'Bebidas',10.70),
      (325,N'Detergente en polvo para ropa blanca 4 kg',N'Ariel',N'Limpieza',36.90),
      (326,N'Detergente en polvo ropa de color 4 kg',N'Ace',N'Limpieza',31.90),
      (327,N'Jabón para ropa floral 210 g',N'Bolívar',N'Limpieza',7.10),
      (328,N'Lavavajillas líquido naranja 750 ml',N'Sapolio',N'Limpieza',10.20),
      (329,N'Lavavajillas en pasta naranja 450 g',N'Ayudín',N'Limpieza',4.90),
      (330,N'Limpiador multiuso floral 450 ml',N'Poett',N'Limpieza',6.70),
      (331,N'Lejía aroma floral 2 L',N'Sapolio',N'Limpieza',12.20),
      (332,N'Lejía limón 1 L',N'Clorox',N'Limpieza',9.30),
      (333,N'Limpiador de cocina limón 1 L',N'Mr. Músculo',N'Limpieza',14.00),
      (334,N'Limpiador de baño desinfectante 1 L',N'Harpic',N'Limpieza',14.50),
      (335,N'Papel higiénico suave 24 rollos',N'Elite',N'Limpieza',28.80),
      (336,N'Papel higiénico acolchado 4 rollos',N'Suave',N'Limpieza',19.10),
      (337,N'Papel toalla multiuso 2 rollos',N'Scott',N'Limpieza',15.60),
      (338,N'Servilletas de papel blancas 200 unidades',N'Elite',N'Limpieza',4.50),
      (339,N'Suavizante de ropa lavanda 400 ml',N'Downy',N'Limpieza',11.60),
      (340,N'Suavizante de ropa bebé 800 ml',N'Suavitel',N'Limpieza',16.20);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (341,N'Insecticida doméstico multiinsectos 235 ml',N'Raid',N'Limpieza',9.30),
      (342,N'Esponja de cocina doble uso 6 unidades',N'Sapolio',N'Limpieza',5.80),
      (343,N'Paños de limpieza absorbentes 6 unidades',N'Virutex',N'Limpieza',9.40),
      (344,N'Ambientador floral 400 ml',N'Glade',N'Limpieza',9.60),
      (345,N'Pasta dental blanqueadora 100 ml',N'Colgate',N'Cuidado personal',5.00),
      (346,N'Pasta dental menta 100 ml',N'Oral-B',N'Cuidado personal',6.00),
      (347,N'Champú control grasa 650 ml',N'Head & Shoulders',N'Cuidado personal',28.00),
      (348,N'Champú rizos definidos 400 ml',N'Pantene',N'Cuidado personal',16.80),
      (349,N'Acondicionador reparación 200 ml',N'Pantene',N'Cuidado personal',9.00),
      (350,N'Champú rizos 340 ml',N'Sedal',N'Cuidado personal',17.20),
      (351,N'Crema corporal piel sensible 400 ml',N'Nivea',N'Cuidado personal',15.20),
      (352,N'Jabón de tocador piel sensible 180 g',N'Dove',N'Cuidado personal',4.00),
      (353,N'Jabón de tocador avena 180 g',N'Protex',N'Cuidado personal',4.10),
      (354,N'Desodorante invisible 200 ml',N'Rexona',N'Cuidado personal',6.60),
      (355,N'Máquinas de afeitar 2 hojas 4 unidades',N'Gillette',N'Cuidado personal',18.90),
      (356,N'Espuma de afeitar hidratante 400 ml',N'Gillette',N'Cuidado personal',11.90),
      (357,N'Toallas higiénicas normal 24 unidades',N'Kotex',N'Cuidado personal',11.30),
      (358,N'Toallas higiénicas normal 8 unidades',N'Nosotras',N'Cuidado personal',15.90),
      (359,N'Cepillo dental suave 2 unidades',N'Oral-B',N'Cuidado personal',9.60),
      (360,N'Enjuague bucal sin alcohol 1 L',N'Listerine',N'Cuidado personal',22.70),
      (361,N'Algodón hidrófilo 200 g',N'Johnson’s',N'Cuidado personal',3.40),
      (362,N'Protector solar FPS 50+ 200 ml',N'Nivea',N'Cuidado personal',18.10),
      (363,N'Crema para manos nutritiva 150 ml',N'Dove',N'Cuidado personal',5.40),
      (364,N'Helado tricolor 2 L',N'D’Onofrio',N'Congelados',30.20),
      (365,N'Helado vainilla 500 ml',N'Artika',N'Congelados',11.50),
      (366,N'Nuggets de pollo crocanes 1 kg',N'San Fernando',N'Congelados',26.00),
      (367,N'Hamburguesas congeladas res 12 unidades',N'Braedt',N'Congelados',35.20),
      (368,N'Papas prefritas corte grueso 750 g',N'McCain',N'Congelados',19.90),
      (369,N'Verduras congeladas zanahoria y arveja 1 kg',N'Bell’s',N'Congelados',13.80),
      (370,N'Frutas congeladas mango 300 g',N'Bell’s',N'Congelados',11.30),
      (371,N'Milanesa de pollo congelada picante 800 g',N'San Fernando',N'Congelados',31.00),
      (372,N'Paletas heladas chocolate 6 unidades',N'D’Onofrio',N'Congelados',14.00),
      (373,N'Pizza congelada jamón y queso 750 g',N'Bell’s',N'Congelados',24.20),
      (374,N'Atún en conserva salsa de tomate 80 g',N'Florida',N'Conservas',4.60),
      (375,N'Atún en conserva con verduras 170 g',N'Campomar',N'Conservas',5.10),
      (376,N'Sardinas en conserva salsa de tomate 170 g',N'Gloria',N'Conservas',4.50),
      (377,N'Choclo en conserva dulce 400 g',N'Bell’s',N'Conservas',5.30),
      (378,N'Arvejas en conserva verdes 400 g',N'Bell’s',N'Conservas',5.10),
      (379,N'Duraznos en almíbar en cubos 200 g',N'Bell’s',N'Conservas',5.40),
      (380,N'Piña en almíbar en rodajas 420 g',N'Bell’s',N'Conservas',9.40),
      (381,N'Pasta de tomate clásica 100 g',N'Del Monte',N'Conservas',3.50),
      (382,N'Aceitunas rellenas 300 g',N'Bell’s',N'Conservas',8.70),
      (383,N'Palmitos en conserva en trozos 200 g',N'Bell’s',N'Conservas',8.20),
      (384,N'Pan de molde integral 350 g',N'Bimbo',N'Panadería',7.50),
      (385,N'Pan para hamburguesa integral 8 unidades',N'Bimbo',N'Panadería',12.40),
      (386,N'Pan para hot dog extra suave 8 unidades',N'Bimbo',N'Panadería',12.70),
      (387,N'Pan artesanal centeno 300 g',N'Pan de la Chola',N'Panadería',12.60),
      (388,N'Tostadas integrales 300 g',N'Bell’s',N'Panadería',5.80),
      (389,N'Galletas de agua clásicas 300 g',N'San Jorge',N'Panadería',5.30),
      (390,N'Queque chocolate 700 g',N'Bimbo',N'Panadería',16.10),
      (391,N'Tortillas para wraps maíz 10 unidades',N'Bell’s',N'Panadería',13.40),
      (392,N'Panetón sin pasas 1 kg',N'Bimbo',N'Panadería',22.00),
      (393,N'Rosquitas anís 150 g',N'Bell’s',N'Panadería',3.70),
      (394,N'Chocolate leche 30 g',N'Sublime',N'Golosinas',7.30),
      (395,N'Chocolate leche 120 g',N'Nestlé',N'Golosinas',4.30),
      (396,N'Grageas de chocolate clásicas 90 g',N'M&M’s',N'Golosinas',4.70),
      (397,N'Gomitas ácidas 100 g',N'Haribo',N'Golosinas',4.50),
      (398,N'Chicle hierbabuena 20 unidades',N'Trident',N'Golosinas',4.50),
      (399,N'Caramelos eucalipto 20 unidades',N'Halls',N'Golosinas',4.00),
      (400,N'Caramelos masticables fresa 200 g',N'Ambrosoli',N'Golosinas',3.80),
      (401,N'Wafers vainilla 60 g',N'Field',N'Golosinas',2.60),
      (402,N'Papas fritas limón 150 g',N'Lay’s',N'Golosinas',3.50),
      (403,N'Nachos picantes 150 g',N'Doritos',N'Golosinas',3.80),
      (404,N'Alimento seco para perros adultos 1 kg',N'Ricocan',N'Mascotas',41.40),
      (405,N'Alimento seco para perros cachorros 1 kg',N'Pedigree',N'Mascotas',42.00),
      (406,N'Alimento seco para gatos gatitos 3 kg',N'Ricocat',N'Mascotas',53.90),
      (407,N'Alimento seco para gatos salmón 8 kg',N'Whiskas',N'Mascotas',59.30),
      (408,N'Alimento húmedo para perros carne 300 g',N'Dog Chow',N'Mascotas',5.90),
      (409,N'Alimento húmedo para gatos salmón 85 g',N'Felix',N'Mascotas',3.60),
      (410,N'Arena sanitaria para gatos aglomerante 10 kg',N'Cat’s Best',N'Mascotas',51.00),
      (411,N'Snacks para perros res 150 g',N'Ricocan',N'Mascotas',5.80),
      (412,N'Snacks para gatos atún 100 g',N'Ricocat',N'Mascotas',3.80),
      (413,N'Champú para mascotas antipulgas 750 ml',N'Hartz',N'Mascotas',24.30),
      (414,N'Pañales talla G 60 unidades',N'Huggies',N'Bebés',62.80),
      (415,N'Pañales talla XG 60 unidades',N'Pampers',N'Bebés',67.20),
      (416,N'Champú para bebé manzanilla 400 ml',N'Johnson’s',N'Bebés',14.60),
      (417,N'Jabón para bebé clásico 180 g',N'Johnson’s',N'Bebés',4.70),
      (418,N'Toallitas húmedas piel sensible 80 unidades',N'Pigeon',N'Bebés',7.30),
      (419,N'Toallitas húmedas clásicas 120 unidades',N'Huggies',N'Bebés',14.80),
      (420,N'Compota para bebé durazno 90 g',N'Gerber',N'Bebés',2.70),
      (421,N'Cereal para bebé avena 100 g',N'Nestlé',N'Bebés',5.50),
      (422,N'Crema para bebé piel sensible 400 ml',N'Johnson’s',N'Bebés',12.80),
      (423,N'Pañales tipo calzón talla G 48 unidades',N'Huggies',N'Bebés',64.60),
      (424,N'Manzana empacada verde 500 g',N'Fresco',N'Frutas y verduras',7.20),
      (425,N'Pera empacada abate 500 g',N'Fresco',N'Frutas y verduras',7.50),
      (426,N'Uva empacada sin semilla 500 g',N'Fresco',N'Frutas y verduras',7.40),
      (427,N'Mandarina empacada criolla 500 g',N'Fresco',N'Frutas y verduras',5.10),
      (428,N'Naranja empacada valencia 500 g',N'Fresco',N'Frutas y verduras',4.90),
      (429,N'Plátano empacado bellaco 500 g',N'Fresco',N'Frutas y verduras',4.90),
      (430,N'Tomate empacado saladette 1 kg',N'Fresco',N'Frutas y verduras',9.30),
      (431,N'Papa empacada huayro 500 g',N'Fresco',N'Frutas y verduras',5.40),
      (432,N'Cebolla empacada china 500 g',N'Fresco',N'Frutas y verduras',5.20),
      (433,N'Lechuga empacada americana 2 unidades',N'Fresco',N'Frutas y verduras',5.20),
      (434,N'Zanahoria empacada seleccionada 500 g',N'Fresco',N'Frutas y verduras',4.20),
      (435,N'Palta empacada hass 2 kg',N'Fresco',N'Frutas y verduras',21.70),
      (436,N'Pechuga de pollo marinada 1 kg',N'San Fernando',N'Carnes y embutidos',21.30),
      (437,N'Pierna de pollo con encuentro 1 kg',N'San Fernando',N'Carnes y embutidos',16.10),
      (438,N'Carne molida res especial 2 kg',N'Redondos',N'Carnes y embutidos',39.80),
      (439,N'Bistec de res cadera 1 kg',N'Redondos',N'Carnes y embutidos',37.90),
      (440,N'Jamón de pavo clásico 250 g',N'San Fernando',N'Carnes y embutidos',5.80);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (441,N'Jamón inglés ahumado 100 g',N'Braedt',N'Carnes y embutidos',6.50),
      (442,N'Salchicha de pavo 500 g',N'Braedt',N'Carnes y embutidos',8.90),
      (443,N'Chorizo ahumado 1 kg',N'San Fernando',N'Carnes y embutidos',18.50),
      (444,N'Salame picante 250 g',N'Otto Kunz',N'Carnes y embutidos',8.60),
      (445,N'Tocino clásico 100 g',N'Braedt',N'Carnes y embutidos',7.90),
      (446,N'Papel aluminio extra ancho 5 m',N'Reynolds',N'Hogar',16.70),
      (447,N'Film plástico resistente 60 m',N'Alpesa',N'Hogar',5.60),
      (448,N'Bolsas para basura grandes 20 unidades',N'Duraplast',N'Hogar',9.70),
      (449,N'Bolsas herméticas medianas 40 unidades',N'Ziploc',N'Hogar',18.30),
      (450,N'Pañuelos faciales suaves 50 unidades',N'Kleenex',N'Hogar',5.30),
      (451,N'Velas aromáticas frutos rojos 4 unidades',N'Glade',N'Hogar',15.30),
      (452,N'Encendedores colores 4 unidades',N'Bic',N'Hogar',8.40),
      (453,N'Pilas alcalinas AAA 2 unidades',N'Varta',N'Hogar',13.00),
      (454,N'Esponja de cocina antiadherente 2 unidades',N'Tramontina',N'Hogar',6.80),
      (455,N'Guantes de limpieza talla L 1 par',N'Scotch-Brite',N'Hogar',10.80),
      (456,N'Barra de cereal chocolate 25 g',N'Cerevita',N'Bienestar',5.60),
      (457,N'Barra de granola miel 80 g',N'Nature Valley',N'Bienestar',4.10),
      (458,N'Galletas de avena manzana 60 g',N'Quaker',N'Bienestar',3.70),
      (459,N'Frutos secos pasas 200 g',N'Bell’s',N'Bienestar',9.00),
      (460,N'Semillas ajonjolí 250 g',N'Bell’s',N'Bienestar',6.60),
      (461,N'Mantequilla de almendras natural 700 g',N'Bell’s',N'Bienestar',27.60),
      (462,N'Mix de frutos secos con nueces 100 g',N'Granuts',N'Bienestar',7.60),
      (463,N'Quinua blanca 250 g',N'Bell’s',N'Bienestar',5.40),
      (464,N'Kiwicha orgánica 1 kg',N'Bell’s',N'Bienestar',13.20),
      (465,N'Miel de abeja de algarrobo 750 g',N'Bell’s',N'Bienestar',23.10),
      (466,N'Leche evaporada semidescremada 170 g',N'Gloria',N'Lácteos',2.60),
      (467,N'Leche fresca entera 1 L',N'Laive',N'Lácteos',8.40),
      (468,N'Leche fresca sin lactosa 1 L',N'Gloria',N'Lácteos',7.10),
      (469,N'Yogur bebible durazno 1.8 L',N'Gloria',N'Lácteos',14.70),
      (470,N'Yogur bebible piña 1.8 L',N'Laive',N'Lácteos',15.60),
      (471,N'Yogur griego vainilla 500 g',N'Danlac',N'Lácteos',5.90),
      (472,N'Queso fresco bajo en sal 350 g',N'Laive',N'Lácteos',9.90),
      (473,N'Queso mozzarella en bloque 150 g',N'Bonlé',N'Lácteos',7.00),
      (474,N'Queso edam en bloque 350 g',N'Laive',N'Lácteos',14.60),
      (475,N'Mantequilla con sal 200 g',N'Laive',N'Lácteos',4.90),
      (476,N'Crema de leche clásica 1 L',N'Nestlé',N'Lácteos',9.20),
      (477,N'Manjar blanco tradicional 400 g',N'Gloria',N'Lácteos',6.30),
      (478,N'Leche en polvo entera 800 g',N'Gloria',N'Lácteos',18.40),
      (479,N'Leche condensada light 393 g',N'Nestlé',N'Lácteos',6.60),
      (480,N'Arroz extra 1 kg',N'Costeño',N'Abarrotes',14.80),
      (481,N'Arroz extra 2 kg',N'Paisana',N'Abarrotes',20.70),
      (482,N'Azúcar blanca 5 kg',N'Cartavio',N'Abarrotes',10.30),
      (483,N'Fideos canuto 250 g',N'Molitalia',N'Abarrotes',2.50),
      (484,N'Fideos corbata 1 kg',N'Don Vittorio',N'Abarrotes',7.30),
      (485,N'Harina de trigo sin preparar 2 kg',N'Alianza',N'Abarrotes',10.80),
      (486,N'Harina sin preparar 1 kg',N'Blanca Flor',N'Abarrotes',8.20),
      (487,N'Aceite vegetal de girasol 1.8 L',N'Primor',N'Abarrotes',20.50),
      (488,N'Aceite de oliva 1 L',N'Cocinero',N'Abarrotes',21.80),
      (489,N'Mayonesa con limón 250 g',N'AlaCena',N'Abarrotes',4.60),
      (490,N'Kétchup clásico 100 g',N'AlaCena',N'Abarrotes',3.60),
      (491,N'Mostaza clásica 100 g',N'AlaCena',N'Abarrotes',2.80),
      (492,N'Sazonador para pollo 100 g',N'Maggi',N'Abarrotes',2.60),
      (493,N'Condimento molido comino 250 g',N'Sibarita',N'Abarrotes',2.90),
      (494,N'Cubitos de caldo verduras 24 unidades',N'Knorr',N'Abarrotes',7.30),
      (495,N'Avena tradicional 500 g',N'Quaker',N'Abarrotes',7.20),
      (496,N'Cereal chocolate 200 g',N'Nestlé',N'Abarrotes',7.40),
      (497,N'Cereal integral miel 450 g',N'Fitness',N'Abarrotes',13.00),
      (498,N'Galletas chocolate 400 g',N'San Jorge',N'Abarrotes',4.00),
      (499,N'Galletas limón 150 g',N'Field',N'Abarrotes',2.80),
      (500,N'Mermelada piña 500 g',N'Fanny',N'Abarrotes',8.00),
      (501,N'Mermelada durazno 200 g',N'Gloria',N'Abarrotes',5.10),
      (502,N'Cacao en polvo puro 100 g',N'Winter''s',N'Abarrotes',6.30),
      (503,N'Chocolate para taza clásico 360 g',N'Cocoa',N'Abarrotes',11.70),
      (504,N'Avena instantánea 200 g',N'3 Ositos',N'Abarrotes',3.50),
      (505,N'Lentejas extra 1 kg',N'Costeño',N'Abarrotes',11.50),
      (506,N'Frejoles panamito 1 kg',N'Costeño',N'Abarrotes',13.20),
      (507,N'Garbanzos seleccionados 2 kg',N'Costeño',N'Abarrotes',22.60),
      (508,N'Sal de mesa gruesa 1 kg',N'Bell''s',N'Abarrotes',5.00),
      (509,N'Levadura seca 50 g',N'Fleischmann',N'Abarrotes',4.00),
      (510,N'Gelatina limón 150 g',N'Negrita',N'Abarrotes',2.50),
      (511,N'Pudín chocolate 200 g',N'Negrita',N'Abarrotes',2.50),
      (512,N'Vinagre blanco 1 L',N'Bell''s',N'Abarrotes',6.80),
      (513,N'Salsa de soya oscura 150 ml',N'Bell''s',N'Abarrotes',3.60),
      (514,N'Ají en pasta amarillo 100 g',N'Uchucuta',N'Abarrotes',3.60),
      (515,N'Mantequilla de maní cremosa 400 g',N'Bimbo',N'Abarrotes',13.90),
      (516,N'Gaseosa cola sin azúcar 1.5 L',N'Coca-Cola',N'Bebidas',13.20),
      (517,N'Gaseosa original 1.5 L',N'Inca Kola',N'Bebidas',12.60),
      (518,N'Gaseosa limón original 2.25 L',N'Sprite',N'Bebidas',12.00),
      (519,N'Gaseosa piña 500 ml',N'Fanta',N'Bebidas',5.00),
      (520,N'Néctar manzana 1 L',N'Frugos',N'Bebidas',7.40),
      (521,N'Néctar pera 1.5 L',N'Pulp',N'Bebidas',11.00),
      (522,N'Bebida rehidratante manzana 500 ml',N'Sporade',N'Bebidas',5.10),
      (523,N'Bebida isotónica frutos rojos 500 ml',N'Gatorade',N'Bebidas',6.20),
      (524,N'Bebida energética tropical 250 ml',N'Red Bull',N'Bebidas',4.20),
      (525,N'Bebida energética original 473 ml',N'Volt',N'Bebidas',4.00),
      (526,N'Café soluble descafeinado 50 g',N'Nescafé',N'Bebidas',9.00),
      (527,N'Café molido clásico 250 g',N'Altomayo',N'Bebidas',9.40),
      (528,N'Café tostado gourmet 125 g',N'Cafetal',N'Bebidas',23.40),
      (529,N'Infusión té negro 40 sobres',N'McColins',N'Bebidas',7.50),
      (530,N'Té limón 20 sobres',N'Hornimans',N'Bebidas',8.80),
      (531,N'Bebida chocolatada original 1 L',N'Gloria',N'Bebidas',7.60),
      (532,N'Té helado durazno 500 ml',N'Fuze Tea',N'Bebidas',4.10),
      (533,N'Bebida láctea chocolate 1 L',N'Pura Vida',N'Bebidas',6.80),
      (534,N'Detergente en polvo regular 2 kg',N'Ariel',N'Limpieza',36.80),
      (535,N'Detergente en polvo ropa de color 900 g',N'Ace',N'Limpieza',20.90),
      (536,N'Jabón para ropa limón 210 g',N'Bolívar',N'Limpieza',6.90),
      (537,N'Lavavajillas líquido manzana 250 ml',N'Sapolio',N'Limpieza',4.80),
      (538,N'Lavavajillas en pasta limón 450 g',N'Ayudín',N'Limpieza',4.70),
      (539,N'Limpiador multiuso floral 1.8 L',N'Poett',N'Limpieza',16.40),
      (540,N'Lejía aroma floral 500 ml',N'Sapolio',N'Limpieza',4.80);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (541,N'Lejía clásica 500 ml',N'Clorox',N'Limpieza',5.70),
      (542,N'Limpiador de cocina antibacterial 750 ml',N'Mr. Músculo',N'Limpieza',13.80),
      (543,N'Limpiador de baño pino 1 L',N'Harpic',N'Limpieza',14.30),
      (544,N'Papel higiénico doble hoja 12 rollos',N'Elite',N'Limpieza',30.00),
      (545,N'Papel higiénico acolchado 24 rollos',N'Suave',N'Limpieza',26.70),
      (546,N'Papel toalla doble hoja 4 rollos',N'Scott',N'Limpieza',15.40),
      (547,N'Servilletas de papel decoradas 200 unidades',N'Elite',N'Limpieza',4.30),
      (548,N'Suavizante de ropa lavanda 1.5 L',N'Downy',N'Limpieza',27.80),
      (549,N'Suavizante de ropa primavera 1.5 L',N'Suavitel',N'Limpieza',24.30),
      (550,N'Insecticida doméstico multiinsectos 360 ml',N'Raid',N'Limpieza',19.90),
      (551,N'Esponja de cocina abrasiva 2 unidades',N'Sapolio',N'Limpieza',7.00),
      (552,N'Paños de limpieza absorbentes 2 unidades',N'Virutex',N'Limpieza',9.20),
      (553,N'Ambientador floral 500 ml',N'Glade',N'Limpieza',9.40),
      (554,N'Pasta dental blanqueadora 75 ml',N'Colgate',N'Cuidado personal',4.80),
      (555,N'Pasta dental pro salud 100 ml',N'Oral-B',N'Cuidado personal',5.80),
      (556,N'Champú control grasa 375 ml',N'Head & Shoulders',N'Cuidado personal',17.50),
      (557,N'Champú rizos definidos 200 ml',N'Pantene',N'Cuidado personal',10.50),
      (558,N'Acondicionador hidratación 400 ml',N'Pantene',N'Cuidado personal',15.80),
      (559,N'Champú rizos 190 ml',N'Sedal',N'Cuidado personal',17.00),
      (560,N'Crema corporal piel sensible 750 ml',N'Nivea',N'Cuidado personal',24.20),
      (561,N'Jabón de tocador piel sensible 360 g',N'Dove',N'Cuidado personal',8.80),
      (562,N'Jabón de tocador antibacterial 360 g',N'Protex',N'Cuidado personal',8.60),
      (563,N'Desodorante sport 50 ml',N'Rexona',N'Cuidado personal',6.40),
      (564,N'Desodorante fresh 50 ml',N'Nivea',N'Cuidado personal',6.70),
      (565,N'Máquinas de afeitar 3 hojas 2 unidades',N'Gillette',N'Cuidado personal',18.90),
      (566,N'Espuma de afeitar piel sensible 250 ml',N'Gillette',N'Cuidado personal',7.20),
      (567,N'Toallas higiénicas nocturna 24 unidades',N'Nosotras',N'Cuidado personal',11.10),
      (568,N'Cepillo dental ultrasuave 3 unidades',N'Oral-B',N'Cuidado personal',9.40),
      (569,N'Enjuague bucal cuidado total 1 L',N'Listerine',N'Cuidado personal',22.50),
      (570,N'Algodón hidrófilo 50 g',N'Johnson’s',N'Cuidado personal',3.20),
      (571,N'Protector solar FPS 30 50 ml',N'Nivea',N'Cuidado personal',17.90),
      (572,N'Crema para manos nutritiva 300 ml',N'Dove',N'Cuidado personal',10.10),
      (573,N'Helado lúcuma 1 L',N'D’Onofrio',N'Congelados',19.60),
      (574,N'Nuggets de pollo picantes 1 kg',N'San Fernando',N'Congelados',25.60),
      (575,N'Hamburguesas congeladas parrilleras 4 unidades',N'Braedt',N'Congelados',24.80),
      (576,N'Papas prefritas corte fino 400 g',N'McCain',N'Congelados',12.20),
      (577,N'Verduras congeladas brócoli 750 g',N'Bell’s',N'Congelados',13.40),
      (578,N'Frutas congeladas fresa 1 kg',N'Bell’s',N'Congelados',19.40),
      (579,N'Milanesa de pollo congelada clásica 1 kg',N'San Fernando',N'Congelados',32.00),
      (580,N'Paletas heladas fresa 6 unidades',N'D’Onofrio',N'Congelados',13.60),
      (581,N'Pizza congelada mozzarella 500 g',N'Bell’s',N'Congelados',14.70),
      (582,N'Atún en conserva aceite 80 g',N'Florida',N'Conservas',4.30),
      (583,N'Atún en conserva agua 170 g',N'Campomar',N'Conservas',4.80),
      (584,N'Sardinas en conserva picantes 300 g',N'Gloria',N'Conservas',6.50),
      (585,N'Choclo en conserva grano entero 800 g',N'Bell’s',N'Conservas',9.70),
      (586,N'Arvejas en conserva con zanahoria 200 g',N'Bell’s',N'Conservas',4.00),
      (587,N'Duraznos en almíbar en mitades 820 g',N'Bell’s',N'Conservas',11.80),
      (588,N'Piña en almíbar en rodajas 200 g',N'Bell’s',N'Conservas',5.50),
      (589,N'Pasta de tomate condimentada 100 g',N'Del Monte',N'Conservas',3.10),
      (590,N'Aceitunas negras 300 g',N'Bell’s',N'Conservas',8.40),
      (591,N'Palmitos en conserva enteros 400 g',N'Bell’s',N'Conservas',12.40),
      (592,N'Pan de molde multigrano 500 g',N'Bimbo',N'Panadería',8.40),
      (593,N'Pan para hamburguesa clásico 6 unidades',N'Bimbo',N'Panadería',9.70),
      (594,N'Pan para hot dog extra suave 6 unidades',N'Bimbo',N'Panadería',8.60),
      (595,N'Pan artesanal multigrano 500 g',N'Pan de la Chola',N'Panadería',12.20),
      (596,N'Tostadas con semillas 300 g',N'Bell’s',N'Panadería',5.40),
      (597,N'Galletas de agua clásicas 100 g',N'San Jorge',N'Panadería',3.10),
      (598,N'Queque marmoleado 700 g',N'Bimbo',N'Panadería',15.70),
      (599,N'Tortillas para wraps trigo 6 unidades',N'Bell’s',N'Panadería',14.40),
      (600,N'Panetón sin pasas 800 g',N'Bimbo',N'Panadería',23.00),
      (601,N'Rosquitas de mantequilla 150 g',N'Bell’s',N'Panadería',3.30),
      (602,N'Chocolate maní 30 g',N'Sublime',N'Golosinas',6.90),
      (603,N'Chocolate amargo 35 g',N'Nestlé',N'Golosinas',8.90),
      (604,N'Grageas de chocolate maní 180 g',N'M&M’s',N'Golosinas',4.30),
      (605,N'Gomitas ositos 200 g',N'Haribo',N'Golosinas',4.10),
      (606,N'Chicle sandía 10 unidades',N'Trident',N'Golosinas',5.70),
      (607,N'Caramelos miel 5 unidades',N'Halls',N'Golosinas',5.20),
      (608,N'Caramelos masticables fresa 100 g',N'Ambrosoli',N'Golosinas',3.40),
      (609,N'Wafers chocolate 60 g',N'Field',N'Golosinas',2.50),
      (610,N'Papas fritas clásicas 40 g',N'Lay’s',N'Golosinas',7.20),
      (611,N'Nachos picantes 90 g',N'Doritos',N'Golosinas',3.40),
      (612,N'Alimento seco para perros pollo 1 kg',N'Pedigree',N'Mascotas',42.70),
      (613,N'Alimento seco para gatos pollo 3 kg',N'Whiskas',N'Mascotas',59.90),
      (614,N'Alimento húmedo para perros cordero 300 g',N'Dog Chow',N'Mascotas',6.50),
      (615,N'Alimento húmedo para gatos atún 170 g',N'Felix',N'Mascotas',2.80),
      (616,N'Arena sanitaria para gatos sin perfume 2 kg',N'Cat’s Best',N'Mascotas',50.20),
      (617,N'Snacks para perros dentales 300 g',N'Ricocan',N'Mascotas',8.20),
      (618,N'Snacks para gatos pollo 180 g',N'Ricocat',N'Mascotas',4.40),
      (619,N'Champú para mascotas aloe vera 500 ml',N'Hartz',N'Mascotas',15.70),
      (620,N'Pañales talla P 20 unidades',N'Huggies',N'Bebés',43.10),
      (621,N'Champú para bebé manzanilla 200 ml',N'Johnson’s',N'Bebés',9.60),
      (622,N'Jabón para bebé clásico 90 g',N'Johnson’s',N'Bebés',3.80),
      (623,N'Toallitas húmedas sin perfume 80 unidades',N'Pigeon',N'Bebés',6.40),
      (624,N'Toallitas húmedas aloe vera 80 unidades',N'Huggies',N'Bebés',7.10),
      (625,N'Compota para bebé manzana 90 g',N'Gerber',N'Bebés',3.10),
      (626,N'Cereal para bebé multicereal 250 g',N'Nestlé',N'Bebés',5.90),
      (627,N'Crema para bebé con avena 100 ml',N'Johnson’s',N'Bebés',8.40),
      (628,N'Pañales tipo calzón talla XG 48 unidades',N'Huggies',N'Bebés',65.00),
      (629,N'Manzana empacada delicia 2 kg',N'Fresco',N'Frutas y verduras',16.10),
      (630,N'Pera empacada packham 2 kg',N'Fresco',N'Frutas y verduras',16.40),
      (631,N'Uva empacada roja 1 kg',N'Fresco',N'Frutas y verduras',12.50),
      (632,N'Mandarina empacada w. murcott 2 kg',N'Fresco',N'Frutas y verduras',13.30),
      (633,N'Naranja empacada de jugo 1 kg',N'Fresco',N'Frutas y verduras',8.40),
      (634,N'Plátano empacado de isla 1 kg',N'Fresco',N'Frutas y verduras',8.20),
      (635,N'Tomate empacado italiano 250 g',N'Fresco',N'Frutas y verduras',4.10),
      (636,N'Papa empacada amarilla 2 kg',N'Fresco',N'Frutas y verduras',11.70),
      (637,N'Cebolla empacada china 1 kg',N'Fresco',N'Frutas y verduras',7.00),
      (638,N'Lechuga empacada crespa 3 unidades',N'Fresco',N'Frutas y verduras',5.60),
      (639,N'Zanahoria empacada baby 1 kg',N'Fresco',N'Frutas y verduras',7.20),
      (640,N'Palta empacada premium 2 kg',N'Fresco',N'Frutas y verduras',22.10);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (641,N'Pechuga de pollo fileteada 1 kg',N'San Fernando',N'Carnes y embutidos',21.70),
      (642,N'Pierna de pollo con encuentro 500 g',N'San Fernando',N'Carnes y embutidos',10.50),
      (643,N'Carne molida mixta 500 g',N'Redondos',N'Carnes y embutidos',15.60),
      (644,N'Bistec de res cadera 500 g',N'Redondos',N'Carnes y embutidos',23.00),
      (645,N'Jamón de pavo light 100 g',N'San Fernando',N'Carnes y embutidos',6.20),
      (646,N'Jamón inglés light 250 g',N'Braedt',N'Carnes y embutidos',6.90),
      (647,N'Salchicha de pollo 1 kg',N'Braedt',N'Carnes y embutidos',14.70),
      (648,N'Chorizo ahumado 500 g',N'San Fernando',N'Carnes y embutidos',12.00),
      (649,N'Salame picante 100 g',N'Otto Kunz',N'Carnes y embutidos',8.90),
      (650,N'Tocino clásico 250 g',N'Braedt',N'Carnes y embutidos',7.00),
      (651,N'Papel aluminio resistente 10 m',N'Reynolds',N'Hogar',15.70),
      (652,N'Film plástico resistente 30 m',N'Alpesa',N'Hogar',13.60),
      (653,N'Bolsas para basura grandes 30 unidades',N'Duraplast',N'Hogar',10.60),
      (654,N'Bolsas herméticas grandes 40 unidades',N'Ziploc',N'Hogar',18.70),
      (655,N'Pañuelos faciales doble hoja 100 unidades',N'Kleenex',N'Hogar',5.60),
      (656,N'Velas aromáticas lavanda 1 unidad',N'Glade',N'Hogar',15.70),
      (657,N'Encendedores largos 4 unidades',N'Bic',N'Hogar',7.40),
      (658,N'Pilas alcalinas C 8 unidades',N'Varta',N'Hogar',17.00),
      (659,N'Guantes de limpieza talla M 3 pares',N'Scotch-Brite',N'Hogar',11.00),
      (660,N'Barra de cereal frutos rojos 100 g',N'Cerevita',N'Bienestar',2.60),
      (661,N'Barra de granola miel 160 g',N'Nature Valley',N'Bienestar',9.30),
      (662,N'Galletas de avena chocolate 60 g',N'Quaker',N'Bienestar',3.90),
      (663,N'Frutos secos nueces 100 g',N'Bell’s',N'Bienestar',9.20),
      (664,N'Semillas linaza 250 g',N'Bell’s',N'Bienestar',5.50),
      (665,N'Mantequilla de almendras natural 180 g',N'Bell’s',N'Bienestar',10.60),
      (666,N'Mix de frutos secos con nueces 200 g',N'Granuts',N'Bienestar',7.80),
      (667,N'Quinua roja 1 kg',N'Bell’s',N'Bienestar',14.30),
      (668,N'Kiwicha orgánica 500 g',N'Bell’s',N'Bienestar',8.50),
      (669,N'Miel de abeja de algarrobo 350 g',N'Bell’s',N'Bienestar',14.70),
      (670,N'Leche evaporada entera 900 g',N'Gloria',N'Lácteos',6.20),
      (671,N'Leche fresca chocolatada 250 ml',N'Gloria',N'Lácteos',2.50),
      (672,N'Yogur bebible vainilla 1 L',N'Gloria',N'Lácteos',9.50),
      (673,N'Yogur bebible fresa 1.8 L',N'Laive',N'Lácteos',15.60),
      (674,N'Yogur griego arándanos 500 g',N'Danlac',N'Lácteos',5.90),
      (675,N'Queso fresco tradicional 350 g',N'Laive',N'Lácteos',9.90),
      (676,N'Queso mozzarella rallado 300 g',N'Bonlé',N'Lácteos',10.90),
      (677,N'Queso edam en bloque 180 g',N'Laive',N'Lácteos',9.30),
      (678,N'Mantequilla sin sal 400 g',N'Gloria',N'Lácteos',7.70),
      (679,N'Crema de leche clásica 400 ml',N'Nestlé',N'Lácteos',5.60),
      (680,N'Manjar blanco light 400 g',N'Gloria',N'Lácteos',6.30),
      (681,N'Leche en polvo descremada 800 g',N'Gloria',N'Lácteos',18.40),
      (682,N'Leche condensada light 170 g',N'Nestlé',N'Lácteos',4.20),
      (683,N'Arroz añejo 2 kg',N'Costeño',N'Abarrotes',22.30),
      (684,N'Azúcar blanca 1 kg',N'Cartavio',N'Abarrotes',7.70),
      (685,N'Fideos cabello de ángel 500 g',N'Molitalia',N'Abarrotes',3.70),
      (686,N'Fideos corbata 250 g',N'Don Vittorio',N'Abarrotes',2.50),
      (687,N'Harina de trigo integral 500 g',N'Alianza',N'Abarrotes',4.30),
      (688,N'Harina repostera 2 kg',N'Blanca Flor',N'Abarrotes',12.20),
      (689,N'Aceite vegetal de soya 500 ml',N'Primor',N'Abarrotes',8.50),
      (690,N'Aceite de girasol 500 ml',N'Cocinero',N'Abarrotes',13.70),
      (691,N'Mayonesa clásica 850 g',N'AlaCena',N'Abarrotes',12.10),
      (692,N'Kétchup sin azúcar 380 g',N'AlaCena',N'Abarrotes',8.30),
      (693,N'Mostaza dulce 100 g',N'AlaCena',N'Abarrotes',2.60),
      (694,N'Sazonador para guisos 60 g',N'Maggi',N'Abarrotes',2.50),
      (695,N'Condimento molido ají amarillo 100 g',N'Sibarita',N'Abarrotes',2.70),
      (696,N'Cubitos de caldo carne 24 unidades',N'Knorr',N'Abarrotes',7.10),
      (697,N'Avena tradicional 1 kg',N'Quaker',N'Abarrotes',11.00),
      (698,N'Cereal chocolate 700 g',N'Nestlé',N'Abarrotes',20.80),
      (699,N'Cereal integral frutos rojos 200 g',N'Fitness',N'Abarrotes',7.80),
      (700,N'Galletas vainilla 80 g',N'San Jorge',N'Abarrotes',2.50),
      (701,N'Galletas chocolate 150 g',N'Field',N'Abarrotes',2.60),
      (702,N'Mermelada mora 200 g',N'Fanny',N'Abarrotes',4.90),
      (703,N'Mermelada mango 200 g',N'Gloria',N'Abarrotes',5.00),
      (704,N'Cacao en polvo instantáneo 200 g',N'Winter''s',N'Abarrotes',6.10),
      (705,N'Chocolate para taza con canela 90 g',N'Cocoa',N'Abarrotes',6.10),
      (706,N'Avena instantánea 900 g',N'3 Ositos',N'Abarrotes',9.40),
      (707,N'Lentejas seleccionadas 1 kg',N'Costeño',N'Abarrotes',11.30),
      (708,N'Frejoles canario 2 kg',N'Costeño',N'Abarrotes',19.90),
      (709,N'Garbanzos seleccionados 500 g',N'Costeño',N'Abarrotes',9.20),
      (710,N'Sal de mesa yodada 500 g',N'Bell''s',N'Abarrotes',3.10),
      (711,N'Levadura seca 125 g',N'Fleischmann',N'Abarrotes',8.00),
      (712,N'Gelatina piña 80 g',N'Negrita',N'Abarrotes',2.80),
      (713,N'Pudín caramelo 100 g',N'Negrita',N'Abarrotes',2.50),
      (714,N'Vinagre tinto 500 ml',N'Bell''s',N'Abarrotes',4.00),
      (715,N'Salsa de soya clásica 150 ml',N'Bell''s',N'Abarrotes',3.50),
      (716,N'Ají en pasta amarillo 400 g',N'Uchucuta',N'Abarrotes',5.50),
      (717,N'Mantequilla de maní crujiente 750 g',N'Bimbo',N'Abarrotes',21.80),
      (718,N'Gaseosa cola light 2.25 L',N'Coca-Cola',N'Bebidas',13.00),
      (719,N'Gaseosa original 2.25 L',N'Inca Kola',N'Bebidas',13.70),
      (720,N'Gaseosa limón sin azúcar 1.5 L',N'Sprite',N'Bebidas',11.90),
      (721,N'Gaseosa uva 500 ml',N'Fanta',N'Bebidas',4.80),
      (722,N'Agua de mesa sin gas 2.5 L',N'San Luis',N'Bebidas',8.20),
      (723,N'Néctar durazno 200 ml',N'Pulp',N'Bebidas',2.80),
      (724,N'Bebida rehidratante uva 1 L',N'Sporade',N'Bebidas',7.70),
      (725,N'Bebida isotónica limón 750 ml',N'Gatorade',N'Bebidas',9.40),
      (726,N'Bebida energética sin azúcar 250 ml',N'Red Bull',N'Bebidas',5.30),
      (727,N'Bebida energética original 300 ml',N'Volt',N'Bebidas',3.80),
      (728,N'Café soluble clásico 100 g',N'Nescafé',N'Bebidas',8.80),
      (729,N'Café molido intenso 250 g',N'Altomayo',N'Bebidas',9.20),
      (730,N'Café tostado clásico 125 g',N'Cafetal',N'Bebidas',23.20),
      (731,N'Infusión té verde 40 sobres',N'McColins',N'Bebidas',7.30),
      (732,N'Té verde 20 sobres',N'Hornimans',N'Bebidas',8.60),
      (733,N'Bebida chocolatada con avena 1.5 L',N'Gloria',N'Bebidas',13.00),
      (734,N'Té helado durazno 1 L',N'Fuze Tea',N'Bebidas',6.60),
      (735,N'Bebida láctea chocolate 1.5 L',N'Pura Vida',N'Bebidas',10.30),
      (736,N'Detergente en polvo para ropa blanca 450 g',N'Ariel',N'Limpieza',14.90),
      (737,N'Jabón para ropa floral 400 g',N'Bolívar',N'Limpieza',4.70),
      (738,N'Lavavajillas líquido limón 1 L',N'Sapolio',N'Limpieza',11.00),
      (739,N'Lavavajillas en pasta limón 250 g',N'Ayudín',N'Limpieza',3.70),
      (740,N'Limpiador multiuso lavanda 900 ml',N'Poett',N'Limpieza',11.60);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (741,N'Lejía ropa de color 1 L',N'Sapolio',N'Limpieza',7.50),
      (742,N'Lejía antibacterial 2 L',N'Clorox',N'Limpieza',13.40),
      (743,N'Limpiador de cocina antibacterial 1 L',N'Mr. Músculo',N'Limpieza',13.40),
      (744,N'Limpiador de baño cítrico 500 ml',N'Harpic',N'Limpieza',8.70),
      (745,N'Papel higiénico triple hoja 12 rollos',N'Suave',N'Limpieza',27.50),
      (746,N'Papel toalla maxi absorbente 6 rollos',N'Scott',N'Limpieza',16.20),
      (747,N'Servilletas de papel blancas 400 unidades',N'Elite',N'Limpieza',7.80),
      (748,N'Suavizante de ropa frescura de algodón 800 ml',N'Downy',N'Limpieza',17.70),
      (749,N'Suavizante de ropa primavera 800 ml',N'Suavitel',N'Limpieza',15.50),
      (750,N'Insecticida doméstico multiinsectos 450 ml',N'Raid',N'Limpieza',13.80),
      (751,N'Esponja de cocina suave 6 unidades',N'Sapolio',N'Limpieza',6.40),
      (752,N'Paños de limpieza multiuso 4 unidades',N'Virutex',N'Limpieza',10.00),
      (753,N'Ambientador lavanda 500 ml',N'Glade',N'Limpieza',10.20),
      (754,N'Pasta dental máxima protección 75 ml',N'Colgate',N'Cuidado personal',5.50),
      (755,N'Pasta dental pro salud 75 ml',N'Oral-B',N'Cuidado personal',5.20),
      (756,N'Champú hidratación 650 ml',N'Head & Shoulders',N'Cuidado personal',27.20),
      (757,N'Champú antifrizz 400 ml',N'Pantene',N'Cuidado personal',16.00),
      (758,N'Acondicionador rizos definidos 200 ml',N'Pantene',N'Cuidado personal',9.50),
      (759,N'Champú ceramidas 650 ml',N'Sedal',N'Cuidado personal',20.40),
      (760,N'Crema corporal nutritiva 400 ml',N'Nivea',N'Cuidado personal',15.80),
      (761,N'Jabón de tocador humectante 180 g',N'Dove',N'Cuidado personal',4.60),
      (762,N'Jabón de tocador antibacterial 90 g',N'Protex',N'Cuidado personal',3.30),
      (763,N'Desodorante sport 200 ml',N'Rexona',N'Cuidado personal',5.80),
      (764,N'Desodorante fresh 150 ml',N'Nivea',N'Cuidado personal',6.20),
      (765,N'Máquinas de afeitar piel sensible 8 unidades',N'Gillette',N'Cuidado personal',25.60),
      (766,N'Espuma de afeitar hidratante 250 ml',N'Gillette',N'Cuidado personal',8.00),
      (767,N'Toallas higiénicas ultradelgada 16 unidades',N'Nosotras',N'Cuidado personal',11.90),
      (768,N'Cepillo dental suave 1 unidad',N'Oral-B',N'Cuidado personal',10.20),
      (769,N'Enjuague bucal menta 500 ml',N'Listerine',N'Cuidado personal',13.50),
      (770,N'Algodón bolitas 200 g',N'Johnson’s',N'Cuidado personal',2.70),
      (771,N'Protector solar FPS 30 100 ml',N'Nivea',N'Cuidado personal',17.40),
      (772,N'Crema para manos piel seca 75 ml',N'Dove',N'Cuidado personal',5.90),
      (773,N'Helado vainilla 2 L',N'Artika',N'Congelados',28.50),
      (774,N'Nuggets de pollo picantes 250 g',N'San Fernando',N'Congelados',10.60),
      (775,N'Hamburguesas congeladas pollo 8 unidades',N'Braedt',N'Congelados',35.60),
      (776,N'Papas prefritas rústicas 750 g',N'McCain',N'Congelados',19.00),
      (777,N'Verduras congeladas brócoli 400 g',N'Bell’s',N'Congelados',7.90),
      (778,N'Frutas congeladas arándanos 300 g',N'Bell’s',N'Congelados',11.70),
      (779,N'Milanesa de pollo congelada picante 400 g',N'San Fernando',N'Congelados',19.70),
      (780,N'Paletas heladas chocolate 12 unidades',N'D’Onofrio',N'Congelados',20.10),
      (781,N'Pizza congelada mozzarella 350 g',N'Bell’s',N'Congelados',15.50),
      (782,N'Atún en conserva agua 80 g',N'Florida',N'Conservas',5.00),
      (783,N'Sardinas en conserva picantes 90 g',N'Gloria',N'Conservas',3.40),
      (784,N'Choclo en conserva grano entero 400 g',N'Bell’s',N'Conservas',5.50),
      (785,N'Arvejas en conserva con zanahoria 800 g',N'Bell’s',N'Conservas',8.50),
      (786,N'Duraznos en almíbar en cubos 820 g',N'Bell’s',N'Conservas',12.40),
      (787,N'Piña en almíbar en trozos 200 g',N'Bell’s',N'Conservas',6.00),
      (788,N'Pasta de tomate concentrada 400 g',N'Del Monte',N'Conservas',5.60),
      (789,N'Aceitunas verdes 150 g',N'Bell’s',N'Conservas',5.80),
      (790,N'Palmitos en conserva en trozos 800 g',N'Bell’s',N'Conservas',19.00),
      (791,N'Pan de molde blanco 600 g',N'Bimbo',N'Panadería',12.50),
      (792,N'Pan para hamburguesa clásico 4 unidades',N'Bimbo',N'Panadería',8.90),
      (793,N'Pan para hot dog clásico 6 unidades',N'Bimbo',N'Panadería',9.20),
      (794,N'Pan artesanal multigrano 300 g',N'Pan de la Chola',N'Panadería',12.80),
      (795,N'Tostadas con semillas 200 g',N'Bell’s',N'Panadería',3.90),
      (796,N'Galletas de agua saladas 100 g',N'San Jorge',N'Panadería',3.70),
      (797,N'Queque vainilla 700 g',N'Bimbo',N'Panadería',15.00),
      (798,N'Tortillas para wraps integral 10 unidades',N'Bell’s',N'Panadería',13.60),
      (799,N'Panetón clásico 800 g',N'Bimbo',N'Panadería',22.20),
      (800,N'Rosquitas integrales 500 g',N'Bell’s',N'Panadería',6.20),
      (801,N'Chocolate maní 70 g',N'Sublime',N'Golosinas',3.50),
      (802,N'Chocolate leche 35 g',N'Nestlé',N'Golosinas',9.50),
      (803,N'Grageas de chocolate maní 90 g',N'M&M’s',N'Golosinas',4.90),
      (804,N'Gomitas ositos 100 g',N'Haribo',N'Golosinas',3.30),
      (805,N'Chicle fresa 10 unidades',N'Trident',N'Golosinas',4.90),
      (806,N'Caramelos miel 10 unidades',N'Halls',N'Golosinas',4.40),
      (807,N'Caramelos masticables limón 100 g',N'Ambrosoli',N'Golosinas',4.00),
      (808,N'Wafers fresa 60 g',N'Field',N'Golosinas',2.80),
      (809,N'Papas fritas clásicas 150 g',N'Lay’s',N'Golosinas',3.70),
      (810,N'Nachos queso 90 g',N'Doritos',N'Golosinas',3.90),
      (811,N'Alimento seco para perros razas pequeñas 8 kg',N'Ricocan',N'Mascotas',61.60),
      (812,N'Alimento seco para perros carne 3 kg',N'Pedigree',N'Mascotas',64.40),
      (813,N'Alimento seco para gatos esterilizados 1 kg',N'Ricocat',N'Mascotas',35.50),
      (814,N'Alimento seco para gatos gatitos 8 kg',N'Whiskas',N'Mascotas',59.50),
      (815,N'Alimento húmedo para perros pollo 300 g',N'Dog Chow',N'Mascotas',6.10),
      (816,N'Alimento húmedo para gatos atún 340 g',N'Felix',N'Mascotas',8.00),
      (817,N'Arena sanitaria para gatos sin perfume 5 kg',N'Cat’s Best',N'Mascotas',51.10),
      (818,N'Snacks para perros pollo 300 g',N'Ricocan',N'Mascotas',7.80),
      (819,N'Snacks para gatos pollo 50 g',N'Ricocat',N'Mascotas',4.00),
      (820,N'Champú para mascotas aloe vera 250 ml',N'Hartz',N'Mascotas',9.50),
      (821,N'Pañales talla XG 40 unidades',N'Huggies',N'Bebés',45.00),
      (822,N'Pañales talla M 40 unidades',N'Pampers',N'Bebés',48.20),
      (823,N'Champú para bebé clásico 400 ml',N'Johnson’s',N'Bebés',14.80),
      (824,N'Jabón para bebé avena 360 g',N'Johnson’s',N'Bebés',10.20),
      (825,N'Toallitas húmedas piel sensible 120 unidades',N'Pigeon',N'Bebés',13.70),
      (826,N'Toallitas húmedas clásicas 80 unidades',N'Huggies',N'Bebés',6.90),
      (827,N'Compota para bebé pera 90 g',N'Gerber',N'Bebés',2.90),
      (828,N'Cereal para bebé multicereal 100 g',N'Nestlé',N'Bebés',5.70),
      (829,N'Crema para bebé piel sensible 100 ml',N'Johnson’s',N'Bebés',8.20),
      (830,N'Pañales tipo calzón talla XG 16 unidades',N'Huggies',N'Bebés',46.40),
      (831,N'Manzana empacada delicia 500 g',N'Fresco',N'Frutas y verduras',7.40),
      (832,N'Pera empacada packham 500 g',N'Fresco',N'Frutas y verduras',6.30),
      (833,N'Uva empacada verde 2 kg',N'Fresco',N'Frutas y verduras',18.90),
      (834,N'Mandarina empacada criolla 2 kg',N'Fresco',N'Frutas y verduras',13.10),
      (835,N'Naranja empacada de jugo 2 kg',N'Fresco',N'Frutas y verduras',12.40),
      (836,N'Plátano empacado bellaco 1 kg',N'Fresco',N'Frutas y verduras',8.00),
      (837,N'Tomate empacado italiano 1 kg',N'Fresco',N'Frutas y verduras',9.50),
      (838,N'Papa empacada amarilla 1 kg',N'Fresco',N'Frutas y verduras',8.60),
      (839,N'Cebolla empacada roja 2 kg',N'Fresco',N'Frutas y verduras',10.60),
      (840,N'Lechuga empacada americana 1 unidad',N'Fresco',N'Frutas y verduras',5.40);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (841,N'Zanahoria empacada seleccionada 1 kg',N'Fresco',N'Frutas y verduras',7.10),
      (842,N'Palta empacada premium 1 kg',N'Fresco',N'Frutas y verduras',14.40),
      (843,N'Pechuga de pollo sin hueso 500 g',N'San Fernando',N'Carnes y embutidos',13.50),
      (844,N'Pierna de pollo sin encuentro 1 kg',N'San Fernando',N'Carnes y embutidos',16.20),
      (845,N'Carne molida mixta 1 kg',N'Redondos',N'Carnes y embutidos',26.40),
      (846,N'Bistec de res cuadril 500 g',N'Redondos',N'Carnes y embutidos',22.80),
      (847,N'Jamón de pavo light 250 g',N'San Fernando',N'Carnes y embutidos',6.00),
      (848,N'Jamón inglés light 500 g',N'Braedt',N'Carnes y embutidos',10.80),
      (849,N'Salchicha de pollo 500 g',N'Braedt',N'Carnes y embutidos',9.10),
      (850,N'Chorizo parrillero 1 kg',N'San Fernando',N'Carnes y embutidos',18.70),
      (851,N'Salame picante 500 g',N'Otto Kunz',N'Carnes y embutidos',13.80),
      (852,N'Tocino ahumado 250 g',N'Braedt',N'Carnes y embutidos',8.10),
      (853,N'Papel aluminio estándar 10 m',N'Reynolds',N'Hogar',15.50),
      (854,N'Film plástico estándar 60 m',N'Alpesa',N'Hogar',5.80),
      (855,N'Bolsas para basura medianas 10 unidades',N'Duraplast',N'Hogar',10.40),
      (856,N'Bolsas herméticas pequeñas 10 unidades',N'Ziploc',N'Hogar',18.50),
      (857,N'Pañuelos faciales premium 50 unidades',N'Kleenex',N'Hogar',5.50),
      (858,N'Velas aromáticas lavanda 2 unidades',N'Glade',N'Hogar',15.50),
      (859,N'Encendedores colores 1 unidad',N'Bic',N'Hogar',8.60),
      (860,N'Pilas alcalinas AAA 4 unidades',N'Varta',N'Hogar',11.80),
      (861,N'Guantes de limpieza talla M 2 pares',N'Scotch-Brite',N'Hogar',10.80),
      (862,N'Barra de cereal chocolate 50 g',N'Cerevita',N'Bienestar',2.50),
      (863,N'Barra de granola frutos rojos 80 g',N'Nature Valley',N'Bienestar',4.10),
      (864,N'Galletas de avena pasas 60 g',N'Quaker',N'Bienestar',3.70),
      (865,N'Frutos secos pasas 400 g',N'Bell’s',N'Bienestar',14.20),
      (866,N'Semillas girasol 100 g',N'Bell’s',N'Bienestar',6.60),
      (867,N'Mantequilla de almendras natural 350 g',N'Bell’s',N'Bienestar',17.10),
      (868,N'Mix de frutos secos tropical 100 g',N'Granuts',N'Bienestar',7.60),
      (869,N'Quinua roja 500 g',N'Bell’s',N'Bienestar',8.70),
      (870,N'Kiwicha pop 1 kg',N'Bell’s',N'Bienestar',13.20),
      (871,N'Miel de abeja de algarrobo 150 g',N'Bell’s',N'Bienestar',9.10),
      (872,N'Leche evaporada light 170 g',N'Gloria',N'Lácteos',2.60),
      (873,N'Leche fresca descremada 2 L',N'Laive',N'Lácteos',12.50),
      (874,N'Leche fresca chocolatada 2 L',N'Gloria',N'Lácteos',11.20),
      (875,N'Yogur bebible vainilla 1.8 L',N'Gloria',N'Lácteos',14.70),
      (876,N'Yogur bebible natural 180 ml',N'Laive',N'Lácteos',3.90),
      (877,N'Yogur griego natural 500 g',N'Danlac',N'Lácteos',5.90),
      (878,N'Queso fresco light 200 g',N'Laive',N'Lácteos',6.30),
      (879,N'Queso mozzarella rallado 150 g',N'Bonlé',N'Lácteos',7.00),
      (880,N'Queso edam en tajadas 500 g',N'Laive',N'Lácteos',14.60),
      (881,N'Mantequilla con sal 400 g',N'Laive',N'Lácteos',8.10),
      (882,N'Crema de leche ligera 400 ml',N'Nestlé',N'Lácteos',5.60),
      (883,N'Manjar blanco tradicional 900 g',N'Gloria',N'Lácteos',10.20),
      (884,N'Leche en polvo entera 400 g',N'Gloria',N'Lácteos',11.50),
      (885,N'Leche condensada tradicional 393 g',N'Nestlé',N'Lácteos',6.60),
      (886,N'Arroz integral 5 kg',N'Paisana',N'Abarrotes',20.50),
      (887,N'Azúcar extra fina 5 kg',N'Bell''s',N'Abarrotes',10.90),
      (888,N'Fideos cabello de ángel 250 g',N'Molitalia',N'Abarrotes',2.50),
      (889,N'Harina de trigo preparada 1 kg',N'Alianza',N'Abarrotes',6.80),
      (890,N'Harina preparada 2 kg',N'Blanca Flor',N'Abarrotes',12.10),
      (891,N'Aceite vegetal mezcla 1.8 L',N'Primor',N'Abarrotes',20.10),
      (892,N'Aceite de oliva 500 ml',N'Cocinero',N'Abarrotes',13.50),
      (893,N'Mayonesa clásica 250 g',N'AlaCena',N'Abarrotes',5.60),
      (894,N'Kétchup picante 380 g',N'AlaCena',N'Abarrotes',9.50),
      (895,N'Mostaza clásica 500 g',N'AlaCena',N'Abarrotes',4.30),
      (896,N'Sazonador para pollo 60 g',N'Maggi',N'Abarrotes',2.50),
      (897,N'Condimento molido palillo 250 g',N'Sibarita',N'Abarrotes',2.60),
      (898,N'Cubitos de caldo carne 6 unidades',N'Knorr',N'Abarrotes',6.90),
      (899,N'Avena integral 1 kg',N'Quaker',N'Abarrotes',10.80),
      (900,N'Cereal miel 200 g',N'Nestlé',N'Abarrotes',8.30),
      (901,N'Cereal integral chocolate 700 g',N'Fitness',N'Abarrotes',22.00),
      (902,N'Galletas integral 200 g',N'San Jorge',N'Abarrotes',2.50),
      (903,N'Galletas limón 300 g',N'Field',N'Abarrotes',4.10),
      (904,N'Mermelada durazno 350 g',N'Gloria',N'Abarrotes',7.40),
      (905,N'Cacao en polvo con azúcar 400 g',N'Winter''s',N'Abarrotes',9.20),
      (906,N'Chocolate para taza con canela 180 g',N'Cocoa',N'Abarrotes',5.70),
      (907,N'Avena integral 200 g',N'3 Ositos',N'Abarrotes',4.30),
      (908,N'Lentejas extra 2 kg',N'Costeño',N'Abarrotes',18.40),
      (909,N'Frejoles panamito 500 g',N'Costeño',N'Abarrotes',7.70),
      (910,N'Garbanzos seleccionados 1 kg',N'Costeño',N'Abarrotes',14.30),
      (911,N'Sal de mesa marina 500 g',N'Bell''s',N'Abarrotes',2.70),
      (912,N'Levadura seca 11 g',N'Fleischmann',N'Abarrotes',7.60),
      (913,N'Gelatina naranja 200 g',N'Negrita',N'Abarrotes',2.50),
      (914,N'Pudín vainilla 200 g',N'Negrita',N'Abarrotes',3.00),
      (915,N'Vinagre de manzana 500 ml',N'Bell''s',N'Abarrotes',5.00),
      (916,N'Salsa de soya oscura 500 ml',N'Bell''s',N'Abarrotes',5.30),
      (917,N'Ají en pasta panca 200 g',N'Uchucuta',N'Abarrotes',3.00),
      (918,N'Mantequilla de maní crujiente 200 g',N'Bimbo',N'Abarrotes',8.30),
      (919,N'Gaseosa cola light 1 L',N'Coca-Cola',N'Bebidas',8.30),
      (920,N'Gaseosa sin azúcar 1.5 L',N'Inca Kola',N'Bebidas',13.30),
      (921,N'Gaseosa limón sin azúcar 500 ml',N'Sprite',N'Bebidas',5.50),
      (922,N'Gaseosa naranja 2.25 L',N'Fanta',N'Bebidas',13.20),
      (923,N'Agua de mesa con gas 1 L',N'San Luis',N'Bebidas',4.90),
      (924,N'Agua de mesa con gas 2.5 L',N'Cielo',N'Bebidas',7.30),
      (925,N'Néctar mix de frutas 200 ml',N'Frugos',N'Bebidas',2.70),
      (926,N'Néctar durazno 1.5 L',N'Pulp',N'Bebidas',10.80),
      (927,N'Bebida rehidratante naranja 500 ml',N'Sporade',N'Bebidas',4.90),
      (928,N'Bebida isotónica frutos rojos 1 L',N'Gatorade',N'Bebidas',9.40),
      (929,N'Bebida energética sin azúcar 355 ml',N'Red Bull',N'Bebidas',8.10),
      (930,N'Bebida energética citrus 300 ml',N'Volt',N'Bebidas',3.80),
      (931,N'Café soluble suave 200 g',N'Nescafé',N'Bebidas',8.80),
      (932,N'Café molido clásico 500 g',N'Altomayo',N'Bebidas',14.80),
      (933,N'Café tostado extra fuerte 500 g',N'Cafetal',N'Bebidas',16.70),
      (934,N'Infusión té negro 60 sobres',N'McColins',N'Bebidas',3.40),
      (935,N'Té negro 20 sobres',N'Hornimans',N'Bebidas',8.60),
      (936,N'Bebida chocolatada original 1.5 L',N'Gloria',N'Bebidas',13.00),
      (937,N'Té helado limón 1.5 L',N'Fuze Tea',N'Bebidas',10.30),
      (938,N'Bebida láctea fresa 200 ml',N'Pura Vida',N'Bebidas',2.50),
      (939,N'Detergente en polvo para ropa blanca 900 g',N'Ariel',N'Limpieza',24.00),
      (940,N'Detergente en polvo floral 4 kg',N'Ace',N'Limpieza',31.50);

    INSERT INTO #TipoProducto(id,nombre,marca,categoria,precio) VALUES
      (941,N'Jabón para ropa limón 400 g',N'Bolívar',N'Limpieza',4.90),
      (942,N'Lavavajillas líquido antigrasa 500 ml',N'Sapolio',N'Limpieza',7.10),
      (943,N'Lavavajillas en pasta bicarbonato 900 g',N'Ayudín',N'Limpieza',9.00),
      (944,N'Limpiador multiuso primavera 900 ml',N'Poett',N'Limpieza',10.50),
      (945,N'Lejía limón 2 L',N'Clorox',N'Limpieza',13.40),
      (946,N'Limpiador de cocina limón 750 ml',N'Mr. Músculo',N'Limpieza',13.40),
      (947,N'Limpiador de baño cítrico 1 L',N'Harpic',N'Limpieza',13.90),
      (948,N'Papel higiénico acolchado 12 rollos',N'Suave',N'Limpieza',27.50),
      (949,N'Papel toalla maxi absorbente 2 rollos',N'Scott',N'Limpieza',16.20),
      (950,N'Servilletas de papel premium 400 unidades',N'Elite',N'Limpieza',7.80),
      (951,N'Suavizante de ropa floral 1.5 L',N'Downy',N'Limpieza',27.30),
      (952,N'Suavizante de ropa floral 400 ml',N'Suavitel',N'Limpieza',9.60),
      (953,N'Insecticida doméstico para cucarachas 360 ml',N'Raid',N'Limpieza',19.30),
      (954,N'Esponja de cocina doble uso 4 unidades',N'Sapolio',N'Limpieza',6.40),
      (955,N'Paños de limpieza microfibra 2 unidades',N'Virutex',N'Limpieza',10.00),
      (956,N'Ambientador lavanda 270 ml',N'Glade',N'Limpieza',14.00),
      (957,N'Pasta dental sensitive 75 ml',N'Colgate',N'Cuidado personal',5.50),
      (958,N'Pasta dental protección total 75 ml',N'Oral-B',N'Cuidado personal',5.20),
      (959,N'Champú antifrizz 750 ml',N'Pantene',N'Cuidado personal',25.50),
      (960,N'Acondicionador rizos definidos 400 ml',N'Pantene',N'Cuidado personal',15.10),
      (961,N'Champú ceramidas 190 ml',N'Sedal',N'Cuidado personal',17.60),
      (962,N'Crema corporal nutritiva 750 ml',N'Nivea',N'Cuidado personal',24.80),
      (963,N'Jabón de tocador original 90 g',N'Dove',N'Cuidado personal',4.40),
      (964,N'Jabón de tocador aloe vera 90 g',N'Protex',N'Cuidado personal',4.40),
      (965,N'Desodorante dry comfort 150 ml',N'Nivea',N'Cuidado personal',5.80),
      (966,N'Máquinas de afeitar 3 hojas 4 unidades',N'Gillette',N'Cuidado personal',17.90),
      (967,N'Espuma de afeitar clásica 250 ml',N'Gillette',N'Cuidado personal',7.60),
      (968,N'Toallas higiénicas nocturna 16 unidades',N'Kotex',N'Cuidado personal',11.70),
      (969,N'Toallas higiénicas nocturna 8 unidades',N'Nosotras',N'Cuidado personal',16.30),
      (970,N'Cepillo dental ultrasuave 2 unidades',N'Oral-B',N'Cuidado personal',10.00),
      (971,N'Enjuague bucal cuidado total 500 ml',N'Listerine',N'Cuidado personal',14.70),
      (972,N'Algodón discos 200 g',N'Johnson’s',N'Cuidado personal',2.50),
      (973,N'Protector solar FPS 50 100 ml',N'Nivea',N'Cuidado personal',17.20),
      (974,N'Crema para manos aloe vera 150 ml',N'Dove',N'Cuidado personal',5.70),
      (975,N'Helado fresa 1 L',N'D’Onofrio',N'Congelados',20.10),
      (976,N'Helado café 500 ml',N'Artika',N'Congelados',11.90),
      (977,N'Nuggets de pollo clásicos 250 g',N'San Fernando',N'Congelados',10.60),
      (978,N'Hamburguesas congeladas res 4 unidades',N'Braedt',N'Congelados',25.60),
      (979,N'Papas prefritas rústicas 1 kg',N'McCain',N'Congelados',19.00),
      (980,N'Verduras congeladas zanahoria y arveja 750 g',N'Bell’s',N'Congelados',12.80),
      (981,N'Frutas congeladas mix tropical 500 g',N'Bell’s',N'Congelados',11.70),
      (982,N'Milanesa de pollo congelada picante 1 kg',N'San Fernando',N'Congelados',31.40),
      (983,N'Paletas heladas fresa 4 unidades',N'D’Onofrio',N'Congelados',14.40),
      (984,N'Pizza congelada jamón y queso 350 g',N'Bell’s',N'Congelados',15.50),
      (985,N'Atún en conserva vegetal 170 g',N'Florida',N'Conservas',5.00),
      (986,N'Atún en conserva con verduras 300 g',N'Campomar',N'Conservas',7.10),
      (987,N'Sardinas en conserva aceite 90 g',N'Gloria',N'Conservas',3.60),
      (988,N'Choclo en conserva dulce 800 g',N'Bell’s',N'Conservas',9.10),
      (989,N'Arvejas en conserva con zanahoria 400 g',N'Bell’s',N'Conservas',5.50),
      (990,N'Duraznos en almíbar en mitades 200 g',N'Bell’s',N'Conservas',5.80),
      (991,N'Piña en almíbar light 820 g',N'Bell’s',N'Conservas',13.40),
      (992,N'Pasta de tomate clásica 400 g',N'Del Monte',N'Conservas',5.80),
      (993,N'Aceitunas negras 500 g',N'Bell’s',N'Conservas',7.80),
      (994,N'Palmitos en conserva en trozos 400 g',N'Bell’s',N'Conservas',11.90),
      (995,N'Pan de molde multigrano 350 g',N'Bimbo',N'Panadería',7.90),
      (996,N'Pan para hamburguesa con ajonjolí 4 unidades',N'Bimbo',N'Panadería',9.10),
      (997,N'Pan para hot dog integral 6 unidades',N'Bimbo',N'Panadería',9.40),
      (998,N'Pan artesanal multigrano 800 g',N'Pan de la Chola',N'Panadería',20.50),
      (999,N'Tostadas con semillas 100 g',N'Bell’s',N'Panadería',4.10),
      (1000,N'Galletas de agua integrales 300 g',N'San Jorge',N'Panadería',4.40);



    /* El nombre + marca representa un mismo SKU del catalogo de prueba.
       Unicidad garantizada en OLTP y BI por las restricciones de sus tablas. */
    IF EXISTS (
        SELECT nombre FROM #TipoProducto
        GROUP BY nombre HAVING COUNT(*)>1
    ) OR (SELECT COUNT_BIG(*) FROM #TipoProducto)<>1000
      THROW 52002,'El catalogo no tiene 1000 nombres de producto unicos.',1;
    IF EXISTS (SELECT 1 FROM #TipoProducto WHERE precio IS NULL OR precio<=0)
      THROW 52010,'Un producto no tiene precio valido.',1;

    INSERT INTO operacion.Producto
        (codigo_barra,nombre,marca,categoria,precio_actual,activo)
    SELECT CONCAT('DEMO-G6-P-',RIGHT('00000'+CONVERT(VARCHAR(5),id),5)),
           nombre,marca,categoria,
           precio,CONVERT(BIT,1)
    FROM #TipoProducto ORDER BY id;

    /* Mapear SIEMPRE mediante codigo unico de producto: nunca inventar otro ID. */
    CREATE TABLE #Producto (n INT PRIMARY KEY,id_producto INT NOT NULL);
    INSERT INTO #Producto(n,id_producto)
    SELECT c.id,p.id_producto
    FROM #TipoProducto c
    JOIN operacion.Producto p ON p.codigo_barra=
         CONCAT('DEMO-G6-P-',RIGHT('00000'+CONVERT(VARCHAR(5),c.id),5));

    /* 5) Solo 50 tiendas. */
    INSERT INTO operacion.Tienda(nombre,distrito)
    SELECT CONCAT(N'Sucursal DEMO G6 ',RIGHT('00000'+CONVERT(VARCHAR(5),n),5)),
           CASE n%10 WHEN 0 THEN N'San Miguel' WHEN 1 THEN N'Miraflores'
                WHEN 2 THEN N'Santiago de Surco' WHEN 3 THEN N'Los Olivos'
                WHEN 4 THEN N'La Molina' WHEN 5 THEN N'San Borja'
                WHEN 6 THEN N'Comas' WHEN 7 THEN N'Lima Cercado'
                WHEN 8 THEN N'Jesús María' ELSE N'Magdalena del Mar' END
    FROM #N WHERE n<=50 ORDER BY n;

    CREATE TABLE #Tienda(n INT PRIMARY KEY,id_tienda INT NOT NULL);
    INSERT INTO #Tienda(n,id_tienda)
    SELECT x.n,t.id_tienda FROM #N x
    JOIN operacion.Tienda t ON t.nombre=
      CONCAT(N'Sucursal DEMO G6 ',RIGHT('00000'+CONVERT(VARCHAR(5),x.n),5))
    WHERE x.n<=50;

    /* 6) 5000 clientes con DNI SIMULADO, sin datos sensibles reales. */
    DECLARE @Inicio DATE=CONVERT(DATE,'20260101',112);
    INSERT INTO operacion.ClienteAnonimo(dni,fecha_alta)
        SELECT CONVERT(CHAR(8),70000000+n),

           DATEADD(DAY,-(n%720),CONVERT(DATETIME2(0),@Inicio))
    FROM #N ORDER BY n;

    CREATE TABLE #Cliente (n INT PRIMARY KEY,id_cliente BIGINT NOT NULL);
    INSERT INTO #Cliente(n,id_cliente)
    SELECT x.n,c.id_cliente FROM #N x
        JOIN operacion.ClienteAnonimo c ON c.dni=CONVERT(CHAR(8),70000000+x.n);


    /* 7) Cajeros: apellidos n=5001..10000 distintos a los clientes. */
    INSERT INTO operacion.Cajero(codigo_empleado,nombres,apellidos,activo)
    SELECT CONCAT('DEMO-G6-C-',RIGHT('00000'+CONVERT(VARCHAR(5),x.n),5)),
           no.nombre,a.apellidos,CONVERT(BIT,1)
    FROM #N x
    JOIN #Nombre no ON no.id=1+(x.n-1)%40
    JOIN #ApellidosUnicos a ON a.n=x.n+5000
    ORDER BY x.n;

    CREATE TABLE #Cajero(n INT PRIMARY KEY,id_cajero INT NOT NULL);
    INSERT INTO #Cajero(n,id_cajero)
    SELECT x.n,c.id_cajero FROM #N x JOIN operacion.Cajero c
      ON c.codigo_empleado=CONCAT('DEMO-G6-C-',RIGHT('00000'+CONVERT(VARCHAR(5),x.n),5));

    /* 8) Turnos: las 50 tiendas cada dia durante 100 dias.
       Cada tienda recibe exactamente un turno por dia (100 por tienda). */
    INSERT INTO operacion.Turno(id_cajero,id_tienda,inicio,fin)
    SELECT c.id_cajero,t.id_tienda,
           DATEADD(HOUR,8,CONVERT(DATETIME2(0),DATEADD(DAY,(x.n-1)/50,@Inicio))),
           DATEADD(HOUR,16,CONVERT(DATETIME2(0),DATEADD(DAY,(x.n-1)/50,@Inicio)))
    FROM #N x
    JOIN #Cajero c ON c.n=x.n
    JOIN #Tienda t ON t.n=1+(x.n-1)%50;

    CREATE TABLE #Turno(n INT PRIMARY KEY,id_cajero INT NOT NULL,id_tienda INT NOT NULL,
                        inicio DATETIME2(0) NOT NULL);
    INSERT INTO #Turno(n,id_cajero,id_tienda,inicio)
    SELECT x.n,tu.id_cajero,tu.id_tienda,tu.inicio
    FROM #N x JOIN #Cajero c ON c.n=x.n
    JOIN #Tienda t ON t.n=1+(x.n-1)%50
    JOIN operacion.Turno tu ON tu.id_cajero=c.id_cajero AND tu.id_tienda=t.id_tienda
      AND tu.inicio=DATEADD(HOUR,8,CONVERT(DATETIME2(0),DATEADD(DAY,(x.n-1)/50,@Inicio)));

    /* 9) Distribucion de ventas y clientes.
       - Cada uno de los 100 dias tiene 50 ventas (una por tienda).
       - Exactamente una venta anulada por dia, en una tienda que rota
         con el dia. Tras 100 dias: 2 anuladas y 98 pagadas por tienda.
       - Los numeros ordinales de compra se calculan UNICAMENTE para
         ventas pagadas, preservando la segmentacion 4150/250/50/550. */
    CREATE TABLE #EventoEstado (
        n INT NOT NULL PRIMARY KEY,
        anulada BIT NOT NULL,
        ordinal_pagada INT NOT NULL
    );
    ;WITH Estado AS (
        SELECT n,
               CASE WHEN (n-1)%50 = ((n-1)/50)%50
                    THEN 1 ELSE 0 END AS anulada
        FROM #N
    ), Ordenado AS (
        SELECT n,anulada,
               SUM(CASE WHEN anulada=0 THEN 1 ELSE 0 END)
                   OVER (ORDER BY n ROWS UNBOUNDED PRECEDING) AS ordinal_pagada
        FROM Estado
    )
    INSERT INTO #EventoEstado(n,anulada,ordinal_pagada)
    SELECT n,CONVERT(BIT,anulada),ordinal_pagada FROM Ordenado;

    CREATE TABLE #VentaCliente (n INT NOT NULL PRIMARY KEY,id_cliente BIGINT NOT NULL);
    INSERT INTO #VentaCliente(n,id_cliente)
    SELECT e.n,c.id_cliente
    FROM #EventoEstado e
    JOIN #Cliente c ON c.n=CASE
        WHEN e.anulada=1 THEN 1+((e.n*13)%4450)
        WHEN e.ordinal_pagada<=4150 THEN e.ordinal_pagada
        WHEN e.ordinal_pagada<=4650 THEN 4151+(e.ordinal_pagada-4151)/2
        ELSE 4401+(e.ordinal_pagada-4651)/5 END;

    INSERT INTO operacion.Venta
      (id_evento_externo,fecha_venta,id_tienda,id_cliente,id_cajero,canal,metodo_pago,estado)
    SELECT CONCAT('DEMO-G6-V-',RIGHT('000000'+CONVERT(VARCHAR(6),x.n),6)),
           DATEADD(MINUTE,10+x.n%380,tu.inicio),
           tu.id_tienda,vc.id_cliente,tu.id_cajero,
           CASE WHEN x.n%6=0 THEN 'Online' ELSE 'Tienda' END,
           CASE x.n%3 WHEN 0 THEN 'Efectivo' WHEN 1 THEN 'Tarjeta' ELSE 'Billetera' END,
           CASE WHEN e.anulada=1 THEN 'Anulada' ELSE 'Pagada' END
    FROM #N x JOIN #Turno tu ON tu.n=x.n
    JOIN #VentaCliente vc ON vc.n=x.n
    JOIN #EventoEstado e ON e.n=x.n;

    CREATE TABLE #Venta(n INT PRIMARY KEY,id_venta BIGINT NOT NULL);
    INSERT INTO #Venta(n,id_venta)
    SELECT x.n,v.id_venta FROM #N x JOIN operacion.Venta v
      ON v.id_evento_externo=CONCAT('DEMO-G6-V-',RIGHT('000000'+CONVERT(VARCHAR(6),x.n),6));

    /* 10) 15000 lineas, referenciando los MISMOS 1000 IDs de SKU.
           Cada SKU aparece ~15 veces, pero siempre con el mismo id_producto. */
    INSERT INTO operacion.DetalleVenta
      (id_venta,id_producto,nro_linea,cantidad,precio_unitario)
    SELECT v.id_venta,p.id_producto,l.nro_linea,
           1+(x.n+l.nro_linea)%3,pr.precio_actual
    FROM #N x
    JOIN #Venta v ON v.n=x.n
    CROSS JOIN (VALUES(1),(2),(3)) l(nro_linea)
    JOIN #Producto p ON p.n=CASE l.nro_linea
        WHEN 1 THEN 1+(x.n-1)%1000
        WHEN 2 THEN 1+(x.n*7+123)%1000
        ELSE 1+(x.n*13+419)%1000 END
    JOIN operacion.Producto pr ON pr.id_producto=p.id_producto;

    INSERT INTO operacion.Comprobante(id_venta,tipo,serie,numero,estado_envio)
    SELECT v.id_venta,
           CASE WHEN x.n%5=0 THEN 'FACTURA' ELSE 'BOLETA' END,
           CASE WHEN x.n%5=0 THEN 'F001' ELSE 'B001' END,
           x.n,
           CASE WHEN x.n%11=0 THEN 'PENDIENTE' ELSE 'ENVIADO' END
    FROM #N x JOIN #Venta v ON v.n=x.n;

    /* Cada una de las 50 tiendas tiene visitas los mismos 100 dias. */
    INSERT INTO operacion.VisitaAgregada(id_tienda,fecha,visitas_totales,fuente)
    SELECT t.id_tienda,DATEADD(DAY,(x.n-1)/50,@Inicio),
           25+((x.n*17)%95),N'DEMO: conteo simulado, sin identificacion personal'
    FROM #N x JOIN #Tienda t ON t.n=1+(x.n-1)%50;

    /* 11) Dimensiones del Data Mart, derivadas del OLTP (NO duplicadas). */
    INSERT INTO bi.DimFecha(fecha_key,fecha,anio,mes,dia)
    SELECT YEAR(f.fecha)*10000+MONTH(f.fecha)*100+DAY(f.fecha),
           f.fecha,YEAR(f.fecha),MONTH(f.fecha),DAY(f.fecha)
    FROM (
        SELECT DATEADD(DAY,n-1,CONVERT(DATE,'20130101',112)) fecha FROM #N
    ) f;

    INSERT INTO bi.DimProducto(id_producto_oltp,nombre,marca,categoria)
    SELECT p.id_producto,p.nombre,p.marca,p.categoria
    FROM operacion.Producto p ORDER BY p.id_producto;

    INSERT INTO bi.DimTienda(id_tienda_oltp,nombre,distrito)
    SELECT t.id_tienda,t.nombre,t.distrito FROM operacion.Tienda t;

    ;WITH Compras AS (
        SELECT id_cliente,COUNT_BIG(*) cantidad
        FROM operacion.Venta WHERE estado='Pagada' GROUP BY id_cliente
    )
    INSERT INTO bi.DimCliente(id_cliente_oltp,dni,nombres,apellidos,segmento)
    SELECT c.id_cliente,ol.dni,no.nombre,a.apellidos,
           CASE WHEN ISNULL(co.cantidad,0)=0 THEN 'Sin compras'
                WHEN co.cantidad>=5 THEN 'Frecuente'
                WHEN co.cantidad>=2 THEN 'Recurrente'
                ELSE 'Ocasional' END
    FROM #N x
    JOIN #Cliente c ON c.n=x.n
    JOIN operacion.ClienteAnonimo ol ON ol.id_cliente=c.id_cliente
    JOIN #Nombre no ON no.id=1+(x.n-1)%40
    JOIN #ApellidosUnicos a ON a.n=x.n
    LEFT JOIN Compras co ON co.id_cliente=c.id_cliente;

    INSERT INTO bi.DimEmpleado(id_cajero_oltp,codigo_empleado,nombres,apellidos,activo)
    SELECT c.id_cajero,c.codigo_empleado,c.nombres,c.apellidos,c.activo
    FROM operacion.Cajero c;

    /* 12) Hechos: producto_key de bi.DimProducto apunta al unico ID OLTP. */
    INSERT INTO bi.FactDetalleVenta
      (id_detalle_oltp,fecha_key,producto_key,tienda_key,cliente_key,id_venta,cantidad,importe)
    SELECT dv.id_detalle,df.fecha_key,dp.producto_key,dt.tienda_key,dc.cliente_key,
           v.id_venta,dv.cantidad,dv.importe
    FROM operacion.DetalleVenta dv
    JOIN operacion.Venta v ON v.id_venta=dv.id_venta
    JOIN bi.DimFecha df ON df.fecha=CONVERT(DATE,v.fecha_venta)
    JOIN bi.DimProducto dp ON dp.id_producto_oltp=dv.id_producto
    JOIN bi.DimTienda dt ON dt.id_tienda_oltp=v.id_tienda
    LEFT JOIN bi.DimCliente dc ON dc.id_cliente_oltp=v.id_cliente;

    INSERT INTO bi.FactVisitaDiaria(fecha_key,tienda_key,visitas_totales)
    SELECT df.fecha_key,dt.tienda_key,va.visitas_totales
    FROM operacion.VisitaAgregada va
    JOIN bi.DimFecha df ON df.fecha=va.fecha
    JOIN bi.DimTienda dt ON dt.id_tienda_oltp=va.id_tienda;

    INSERT INTO control.Watermark(proceso,ultima_clave,ultima_ejecucion)
    SELECT 'ETL_Detalle',ISNULL(MAX(id_detalle),0),SYSUTCDATETIME()
    FROM operacion.DetalleVenta;

    /* 13) Validacion estricta. Si hay un error, se revierte toda la carga. */
    IF (SELECT COUNT_BIG(*) FROM operacion.Tienda)<>50
       OR (SELECT COUNT_BIG(*) FROM bi.DimTienda)<>50
       THROW 52003,'Debe haber 50 tiendas OLTP y 50 tiendas en BI.',1;
    IF (SELECT COUNT_BIG(*) FROM operacion.Producto)<>1000
       OR (SELECT COUNT_BIG(*) FROM bi.DimProducto)<>1000
       THROW 52004,'Debe haber EXACTAMENTE 1000 productos distintos en OLTP y BI.',1;
    IF (SELECT COUNT_BIG(*) FROM bi.DimCliente)<>5000
       OR (SELECT COUNT_BIG(*) FROM bi.DimEmpleado)<>5000
       THROW 52013,'Deben cargarse los 5000 clientes y los 5000 empleados BI.',1;
    IF (SELECT COUNT_BIG(*) FROM operacion.Venta)<>5000
       OR (SELECT COUNT_BIG(*) FROM operacion.DetalleVenta)<>15000
       OR (SELECT COUNT_BIG(*) FROM bi.FactDetalleVenta)<>15000
       THROW 52005,'La cantidad de ventas o detalles no es correcta.',1;
    /* Validar la participacion real de TODAS las tiendas, no solo que
       aparezcan creadas en DimTienda. */
    IF (SELECT COUNT_BIG(*) FROM operacion.Turno)<>5000
       OR (SELECT COUNT_BIG(*) FROM operacion.VisitaAgregada)<>5000
       OR (SELECT COUNT_BIG(*) FROM bi.FactVisitaDiaria)<>5000
       THROW 52014,'Los turnos o visitas no alcanzan los 5000 registros esperados.',1;

    IF (SELECT COUNT(DISTINCT id_tienda) FROM operacion.Turno)<>50
       OR (SELECT COUNT(DISTINCT id_tienda) FROM operacion.Venta)<>50
       OR (SELECT COUNT(DISTINCT id_tienda) FROM operacion.VisitaAgregada)<>50
       OR (SELECT COUNT(DISTINCT tienda_key) FROM bi.FactDetalleVenta)<>50
       OR (SELECT COUNT(DISTINCT tienda_key) FROM bi.FactVisitaDiaria)<>50
       THROW 52015,'ERROR: al menos una de las 50 tiendas no tiene actividad OLTP y BI.',1;

    IF EXISTS (
        SELECT 1
        FROM operacion.Tienda t
        OUTER APPLY (SELECT COUNT_BIG(*) total FROM operacion.Turno
                     WHERE id_tienda=t.id_tienda) tu
        OUTER APPLY (SELECT COUNT_BIG(*) total FROM operacion.Venta
                     WHERE id_tienda=t.id_tienda) v
        OUTER APPLY (SELECT COUNT_BIG(*) total FROM operacion.Venta
                     WHERE id_tienda=t.id_tienda AND estado='Pagada') vp
        OUTER APPLY (SELECT COUNT_BIG(*) total FROM operacion.Venta
                     WHERE id_tienda=t.id_tienda AND estado='Anulada') va
        OUTER APPLY (SELECT COUNT_BIG(*) total FROM operacion.VisitaAgregada
                     WHERE id_tienda=t.id_tienda) vi
        WHERE tu.total<>100 OR v.total<>100 OR vp.total<>98
           OR va.total<>2 OR vi.total<>100
    ) THROW 52016,'ERROR: distribucion desigual; deben ser 100 turnos, 100 ventas (98 pagadas y 2 anuladas) y 100 visitas diarias por tienda.',1;

     IF EXISTS (
         SELECT 1 FROM operacion.Venta v
         WHERE NOT EXISTS (
             SELECT 1 FROM operacion.Turno tu
             WHERE tu.id_cajero=v.id_cajero AND tu.id_tienda=v.id_tienda
               AND v.fecha_venta>=tu.inicio AND v.fecha_venta<tu.fin
         )
     ) THROW 52017,'ERROR: hay ventas vinculadas a otro turno o fuera del horario.',1;

    IF (SELECT COUNT_BIG(*) FROM operacion.Venta WHERE estado='Pagada')<>4900
       OR (SELECT COUNT_BIG(*) FROM operacion.Venta WHERE estado='Anulada')<>100
       THROW 52018,'ERROR: se esperaban 4900 ventas pagadas y 100 anuladas.',1;

    IF (SELECT COUNT_BIG(*) FROM bi.DimCliente WHERE segmento='Ocasional')<>4150
       OR (SELECT COUNT_BIG(*) FROM bi.DimCliente WHERE segmento='Recurrente')<>250
       OR (SELECT COUNT_BIG(*) FROM bi.DimCliente WHERE segmento='Frecuente')<>50
       OR (SELECT COUNT_BIG(*) FROM bi.DimCliente WHERE segmento='Sin compras')<>550
       THROW 52019,'ERROR: la distribucion de clientes no coincide con el diseño.',1;

    IF EXISTS (SELECT nombre FROM operacion.Producto
               GROUP BY nombre HAVING COUNT(*)>1)
       OR EXISTS (SELECT nombre FROM bi.DimProducto
               GROUP BY nombre HAVING COUNT(*)>1)
       THROW 52011,'ERROR: nombre de producto repetido con un ID distinto.',1;
    IF (SELECT COUNT(DISTINCT id_producto) FROM operacion.DetalleVenta)<>1000
       THROW 52012,'ERROR: se esperaban ventas de los 1000 productos.',1;
    IF EXISTS (SELECT nombre,marca FROM bi.DimProducto
               GROUP BY nombre,marca HAVING COUNT(*)>1)
       THROW 52006,'ERROR: existe un producto repetido con diferentes IDs.',1;
    IF EXISTS (
       SELECT 1 FROM bi.DimProducto d
       LEFT JOIN operacion.Producto p ON p.id_producto=d.id_producto_oltp
       WHERE p.id_producto IS NULL OR p.nombre<>d.nombre OR p.marca<>d.marca
    ) THROW 52007,'ERROR: DimProducto no corresponde con Producto de OLTP.',1;
    IF EXISTS (
       SELECT 1 FROM bi.FactDetalleVenta f
       JOIN operacion.DetalleVenta dv ON dv.id_detalle=f.id_detalle_oltp
       JOIN bi.DimProducto d ON d.producto_key=f.producto_key
       WHERE d.id_producto_oltp<>dv.id_producto
    ) THROW 52008,'ERROR: una venta tiene producto_key distinto al producto OLTP.',1;
    IF EXISTS (SELECT 1 FROM bi.DimCliente GROUP BY apellidos HAVING COUNT(*)>1)
       OR EXISTS (SELECT 1 FROM bi.DimEmpleado GROUP BY apellidos HAVING COUNT(*)>1)
       OR EXISTS (SELECT apellidos FROM bi.DimCliente INTERSECT
                  SELECT apellidos FROM bi.DimEmpleado)
       THROW 52009,'Hay apellidos completos repetidos.',1;

    COMMIT TRANSACTION;
    DROP TABLE IF EXISTS #Venta;
    DROP TABLE IF EXISTS #VentaCliente;
    DROP TABLE IF EXISTS #EventoEstado;
    DROP TABLE IF EXISTS #Turno;
    DROP TABLE IF EXISTS #Cajero;
    DROP TABLE IF EXISTS #Cliente;
    DROP TABLE IF EXISTS #Tienda;
    DROP TABLE IF EXISTS #Producto;
    DROP TABLE IF EXISTS #TipoProducto;
    DROP TABLE IF EXISTS #ApellidosUnicos;
    DROP TABLE IF EXISTS #Apellido;
    DROP TABLE IF EXISTS #Nombre;
    DROP TABLE IF EXISTS #N;
    PRINT N'CORRECTO: base nueva creada con 1000 productos unicos y 50 tiendas ACTIVAS en turnos, ventas, visitas y BI.';
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* 14) Indices para consultas. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'operacion.Venta') AND name=N'IX_Venta_TiendaFecha')
    CREATE INDEX IX_Venta_TiendaFecha ON operacion.Venta(id_tienda,fecha_venta)
  INCLUDE(id_cliente,estado);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'operacion.DetalleVenta') AND name=N'IX_Detalle_Producto')
    CREATE INDEX IX_Detalle_Producto ON operacion.DetalleVenta(id_producto,id_venta)
  INCLUDE(cantidad,importe);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'bi.FactDetalleVenta') AND name=N'IX_FactDetalle_FechaTienda')
    CREATE INDEX IX_FactDetalle_FechaTienda ON bi.FactDetalleVenta(fecha_key,tienda_key)
  INCLUDE(importe,cantidad,producto_key);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'bi.FactVisitaDiaria') AND name=N'IX_FactVisita_TiendaFecha')
    CREATE INDEX IX_FactVisita_TiendaFecha ON bi.FactVisitaDiaria(tienda_key,fecha_key);
GO

/* 15) Comprobar conteos de las 17 tablas. */
SELECT esquema,tabla,total_registros FROM (
 SELECT 'operacion' esquema,'Tienda' tabla,COUNT_BIG(*) total_registros FROM operacion.Tienda
 UNION ALL SELECT 'operacion','Producto',COUNT_BIG(*) FROM operacion.Producto
 UNION ALL SELECT 'operacion','ClienteAnonimo',COUNT_BIG(*) FROM operacion.ClienteAnonimo
 UNION ALL SELECT 'operacion','Cajero',COUNT_BIG(*) FROM operacion.Cajero
 UNION ALL SELECT 'operacion','Turno',COUNT_BIG(*) FROM operacion.Turno
 UNION ALL SELECT 'operacion','Venta',COUNT_BIG(*) FROM operacion.Venta
 UNION ALL SELECT 'operacion','DetalleVenta',COUNT_BIG(*) FROM operacion.DetalleVenta
 UNION ALL SELECT 'operacion','Comprobante',COUNT_BIG(*) FROM operacion.Comprobante
 UNION ALL SELECT 'operacion','VisitaAgregada',COUNT_BIG(*) FROM operacion.VisitaAgregada
 UNION ALL SELECT 'bi','DimFecha',COUNT_BIG(*) FROM bi.DimFecha
 UNION ALL SELECT 'bi','DimProducto',COUNT_BIG(*) FROM bi.DimProducto
 UNION ALL SELECT 'bi','DimTienda',COUNT_BIG(*) FROM bi.DimTienda
 UNION ALL SELECT 'bi','DimCliente',COUNT_BIG(*) FROM bi.DimCliente
 UNION ALL SELECT 'bi','DimEmpleado',COUNT_BIG(*) FROM bi.DimEmpleado
 UNION ALL SELECT 'bi','FactDetalleVenta',COUNT_BIG(*) FROM bi.FactDetalleVenta
 UNION ALL SELECT 'bi','FactVisitaDiaria',COUNT_BIG(*) FROM bi.FactVisitaDiaria
 UNION ALL SELECT 'control','Watermark',COUNT_BIG(*) FROM control.Watermark
) totales ORDER BY esquema,tabla;

/* AUDITORIA DE LAS 50 TIENDAS: cada una debe tener 100 turnos,
   100 ventas, 98 ventas pagadas, 2 anuladas, 100 registros de visitas,
   300 lineas de venta y 300 hechos BI.
   Sin ventas en cero; todas las tiendas quedan activas. */
;WITH Turnos AS (
    SELECT id_tienda,COUNT_BIG(*) turnos FROM operacion.Turno GROUP BY id_tienda
), Ventas AS (
    SELECT id_tienda,COUNT_BIG(*) ventas,
           SUM(CASE WHEN estado='Pagada' THEN 1 ELSE 0 END) ventas_pagadas,
           SUM(CASE WHEN estado='Anulada' THEN 1 ELSE 0 END) ventas_anuladas
    FROM operacion.Venta GROUP BY id_tienda
), Visitas AS (
    SELECT id_tienda,COUNT_BIG(*) dias_con_visitas,
           SUM(CONVERT(BIGINT,visitas_totales)) visitantes_simulados
    FROM operacion.VisitaAgregada GROUP BY id_tienda
), Detalles AS (
    SELECT v.id_tienda, COUNT_BIG(*) lineas_venta
    FROM operacion.Venta v JOIN operacion.DetalleVenta d ON d.id_venta=v.id_venta
    GROUP BY v.id_tienda
), HechosBI AS (
    SELECT d.id_tienda_oltp,COUNT_BIG(*) lineas_bi
    FROM bi.FactDetalleVenta f
    JOIN bi.DimTienda d ON d.tienda_key=f.tienda_key
    GROUP BY d.id_tienda_oltp
), VisitasBI AS (
    SELECT d.id_tienda_oltp,COUNT_BIG(*) dias_bi
    FROM bi.FactVisitaDiaria f
    JOIN bi.DimTienda d ON d.tienda_key=f.tienda_key
    GROUP BY d.id_tienda_oltp
)
SELECT t.id_tienda,t.nombre,
       ISNULL(tu.turnos,0) turnos,
       ISNULL(v.ventas,0) ventas,
       ISNULL(v.ventas_pagadas,0) pagadas,
       ISNULL(v.ventas_anuladas,0) anuladas,
       ISNULL(vi.dias_con_visitas,0) dias_con_visitas,
       ISNULL(vi.visitantes_simulados,0) visitas_totales,
       ISNULL(d.lineas_venta,0) detalles_oltp,
       ISNULL(h.lineas_bi,0) detalles_bi,
       ISNULL(vb.dias_bi,0) dias_visitas_bi,
       CASE WHEN ISNULL(tu.turnos,0)=100 AND ISNULL(v.ventas,0)=100
                      AND ISNULL(v.ventas_pagadas,0)=98
                      AND ISNULL(v.ventas_anuladas,0)=2
                      AND ISNULL(vi.dias_con_visitas,0)=100
                      AND ISNULL(d.lineas_venta,0)=300
                      AND ISNULL(h.lineas_bi,0)=300 AND ISNULL(vb.dias_bi,0)=100
            THEN 'ACTIVA - OK' ELSE 'REVISAR' END estado_validacion
FROM operacion.Tienda t
LEFT JOIN Turnos tu ON tu.id_tienda=t.id_tienda
LEFT JOIN Ventas v ON v.id_tienda=t.id_tienda
LEFT JOIN Visitas vi ON vi.id_tienda=t.id_tienda
LEFT JOIN Detalles d ON d.id_tienda=t.id_tienda
LEFT JOIN HechosBI h ON h.id_tienda_oltp=t.id_tienda
LEFT JOIN VisitasBI vb ON vb.id_tienda_oltp=t.id_tienda
ORDER BY t.id_tienda;

/* Resumen global: deben aparecer 50 tiendas activas en cada componente. */
SELECT (SELECT COUNT_BIG(*) FROM operacion.Tienda) tiendas_registradas,
       (SELECT COUNT(DISTINCT id_tienda) FROM operacion.Turno) tiendas_con_turnos,
       (SELECT COUNT(DISTINCT id_tienda) FROM operacion.Venta WHERE estado='Pagada') tiendas_con_ventas_pagadas,
       (SELECT COUNT(DISTINCT id_tienda) FROM operacion.VisitaAgregada) tiendas_con_visitas,
       (SELECT COUNT(DISTINCT tienda_key) FROM bi.FactDetalleVenta) tiendas_con_hechos_bi,
       (SELECT COUNT(DISTINCT tienda_key) FROM bi.FactVisitaDiaria) tiendas_con_visitas_bi;

/* Ver los 1000 productos distintos y su relacion UNO A UNO. */
SELECT d.producto_key,d.id_producto_oltp,p.id_producto,d.nombre,d.marca,d.categoria
FROM bi.DimProducto d
JOIN operacion.Producto p ON p.id_producto=d.id_producto_oltp
ORDER BY d.id_producto_oltp;

/* Distribucion del catalogo por categoria; todas las filas son SKUs distintos. */
SELECT categoria, COUNT(*) AS total_productos
FROM operacion.Producto
GROUP BY categoria ORDER BY total_productos DESC;

/* Ver que el mismo producto mantiene el ID en varias ventas. */
SELECT TOP (15) p.id_producto,p.nombre,p.marca,
       COUNT(*) AS veces_en_detalle_venta,
       COUNT(DISTINCT dv.id_venta) AS ventas_distintas
FROM operacion.Producto p
JOIN operacion.DetalleVenta dv ON dv.id_producto=p.id_producto
GROUP BY p.id_producto,p.nombre,p.marca
ORDER BY COUNT(*) DESC,p.id_producto;

/* Debe devolver CERO filas: nombres repetidos en bi.DimProducto. */
SELECT nombre,COUNT(*) AS repeticiones
FROM bi.DimProducto
GROUP BY nombre
HAVING COUNT(*)>1;

/* Revisar los segmentos de clientes. */
SELECT segmento,COUNT(*) AS clientes
FROM bi.DimCliente
GROUP BY segmento ORDER BY clientes DESC;

/* La FK OLTP y la integridad de productos deben estar activas. */
SELECT name AS nombre_clave_foranea,is_disabled,is_not_trusted
FROM sys.foreign_keys
WHERE parent_object_id=OBJECT_ID(N'bi.DimProducto');
GO


-- Ver el catálogo único de productos
SELECT 
    id_producto_oltp,
    nombre,
    marca,
    categoria
FROM bi.DimProducto
ORDER BY nombre;

--ver todos los productos repetidos
SELECT
    dp.id_producto_oltp,
    dp.nombre,
    p.marca,
    v.id_tienda,
    dv.id_venta,
    dv.cantidad,
    dv.precio_unitario
FROM bi.DimProducto dp
JOIN operacion.Producto p
    ON p.id_producto = dp.id_producto_oltp
JOIN operacion.DetalleVenta dv
    ON dv.id_producto = p.id_producto
JOIN operacion.Venta v
    ON v.id_venta = dv.id_venta
ORDER BY dp.nombre, dp.id_producto_oltp, v.id_tienda;

--cuantas repeticiones hubo

SELECT
    dp.id_producto_oltp,
    dp.nombre,
    COUNT(*) AS repeticiones
FROM bi.DimProducto dp
JOIN operacion.DetalleVenta dv
    ON dv.id_producto = dp.id_producto_oltp
GROUP BY dp.id_producto_oltp, dp.nombre
ORDER BY dp.nombre;