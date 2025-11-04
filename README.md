# Smart Contract - KipuBank
**🎯 Objetivo**<br/>
Este smart contract esta diseñado para depositar y retirar fondos en distintos tokens, como ETH y tokens ERC-20.

## Funcionalidades del Contrato
- Depositar ETH y ERC-20
- Retirar ETH y ERC-20
- Consultar Balance del usuario
- Control de Acceso por Roles
 - **ADMIN_ROLE**: Función de agregar tokens
 - **AUDITOR_ROLE**: Consulta los balances y **bankCap** de KipuBank
- Eventos y Manejo de Errores

## Cambios Realizados
- Se permite ERC-20
- Se implementó **ADMIN_ROLE** para administración general del contrato
- Se implementó **AUDITOR_ROLE** para consultas tanto de balances como de límites
- Nuevos errores y eventos específicos para diferentes funciones 

## Instrucciones de Deploy
- Crear o Copiar el archivo [KipuBankV2.sol](src/KipuBankV2.sol)
- Compilar el contrato con Solidity ≥ 0.8.20
- En el apartado de Deploy and Run deberás ingresar los parámetros requeridos(bankCapUSDC, limitWithdrawalUSDC)
- Dar click en **Deploy**
- **NOTA:** Si estas utilizando un Injected Provider (Metamask, Rainbow, etc) deberás confirmar la transacción en tu wallet

## Interacción con el Contrato
- **Agregar Token:**
 - Esta función solo es permitida para **ADMIN_ROLE**
 - Parámetros ⇒ Dirección del token, Decimales del token y Dirección del Feed
- **Depositar:**
 - Selecciona tu cuenta y el token a depositar
 - Escribe la cantidad a depositar y haz click en `depositETH` o `depositERC20`
 - **OJO:** Se verifica que no hayas excedido el bankCap
- **Retirar / Withdraw:**
 - Escribe la cantidad y token a retirar
 - **OJO:** Se hacen respectivas validaciones de que la cantidad no sea cero, ni mayor al limite de retiros y que exceda el balance actual del usuario
- **Ver Balance:**
 - Escribe la dirección del usuario y el token
 - Devolverá el balance en **WEI** o en token **ERC-20**


## Adicional
Si deseas trabajar con el código fuente:
```bash
git clone https://github.com/JacobEscoto/KipuBankV2.git
cd KipuBankV2
```

