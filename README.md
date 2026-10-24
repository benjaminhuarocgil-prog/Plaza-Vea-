# Proyecto Plaza Vea: Solución de BI y Big Data

## 1. Descripción del proyecto

Este proyecto académico desarrolla una solución de base de datos e Inteligencia de Negocios (BI) inspirada en las operaciones de Plaza Vea. Su finalidad es organizar información relacionada con productos, tiendas, clientes, empleados y ventas, para facilitar su consulta y análisis.

La implementación principal se realiza mediante un script SQL para SQL Server, que crea las tablas operativas, establece relaciones entre ellas y prepara un modelo de datos orientado a Business Intelligence.

Los datos utilizados son sintéticos y tienen fines académicos; no representan registros reales de Plaza Vea.

## 2. Objetivos

- Diseñar e implementar una base de datos relacional para representar las operaciones de una empresa minorista.
- Mantener la integridad de los datos mediante claves primarias, claves foráneas y restricciones de unicidad.
- Organizar la información en un modelo de datos para análisis mediante BI.
- Preparar una base para estudiar las ventas, los productos, las tiendas y las visitas.
- Documentar las pruebas, los resultados y las versiones del proyecto.

## 3. Tecnologías utilizadas

- **Microsoft SQL Server 2019 o superior:** implementación de la base de datos.
- **SQL:** creación de tablas, relaciones, inserción de datos y validaciones.
- **GitHub:** almacenamiento del código fuente y control de versiones.

## 4. Estructura de la solución

La base de datos se denomina `PlazaVea_G6_1000Productos_50Tiendas` y utiliza tres esquemas:

- **operacion:** contiene las tablas relacionadas con tiendas, productos, clientes, cajeros, turnos, ventas, detalles de venta, comprobantes y visitas.
- **bi:** contiene las dimensiones y tablas de hechos destinadas al análisis de la información.
- **control:** incluye la tabla de control del proceso de carga.

El script contempla 17 tablas y prepara datos sintéticos para representar la actividad de 50 tiendas, un catálogo de 1 000 productos únicos, 5 000 ventas y 15 000 detalles de venta.

Estas cantidades corresponden al diseño del script y deben verificarse mediante su ejecución en SQL Server.

## 5. Archivo principal

`PlazaVea_G6_COMPLETO_1000_PRODUCTOS_50_TIENDAS_ACTIVAS.sql`

Este archivo contiene la implementación principal de la base de datos. Incluye:

- Creación de esquemas y tablas.
- Definición de claves y relaciones.
- Inserción de datos sintéticos.
- Preparación de tablas para Business Intelligence.
- Validaciones de integridad y unicidad.
- Creación de índices para apoyar las consultas.

## 6. Requisitos

- Microsoft SQL Server 2019 o superior.
- SQL Server Management Studio (SSMS).
- Permisos suficientes para crear y utilizar una base de datos.

## 7. Cómo ejecutar el proyecto

1. Abrir SQL Server Management Studio.
2. Conectarse a una instancia de SQL Server.
3. Abrir el script SQL del proyecto.
4. Revisar las instrucciones antes de ejecutarlo.
5. Ejecutar el script en el entorno de desarrollo.
6. Comprobar la creación de las tablas, los registros insertados y las relaciones.

**Importante:** el script está diseñado para inicializar la solución desde cero. Si detecta datos existentes en determinadas tablas, cancela la carga para evitar duplicarlos. Se recomienda utilizar una base de datos de prueba y revisar las instrucciones antes de ejecutarlo.

## 8. Datos y responsabilidad

La información generada se utiliza únicamente con fines académicos. Los nombres, códigos y demás datos de prueba son sintéticos.

Las pruebas de ejecución, las medidas de rendimiento y los controles de seguridad deben documentarse según lo que efectivamente se haya implementado y verificado.

## 9. Integrantes

- Sebastian Elmer Aguilar Obando
- Dylan Conrad Cotrina Portilla
- Benjamin Leonard Huaroc Gil
- Alexander Joshef Palomino León
- Yampier Andre Leon Mendoza

## 10. Estado del proyecto

Proyecto académico en desarrollo. La implementación SQL se encuentra documentada en el script principal; la ejecución, las evidencias de validación y los componentes complementarios deben confirmarse y actualizarse conforme avance el equipo.
