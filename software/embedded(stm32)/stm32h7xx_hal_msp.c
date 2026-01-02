/* USER CODE BEGIN Header */
/**
 * Script Name: stm32h7xx_hal_msp.c
 * Description:
 *   MCU Support Package (MSP) file for the STM32H7. This file handles the
 *   low-level hardware initialization (clocks, GPIO pins, DMA channels, and
 *   IRQs) for the peripherals used in the camera system (DCMI, I2C1).
 *
// all code written by me with minimal AI assistance, comments added using AI
and verified by me
 */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */
extern DMA_HandleTypeDef hdma_dcmi;

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN TD */

/* USER CODE END TD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN Define */

/* USER CODE END Define */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN Macro */

/* USER CODE END Macro */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* External functions --------------------------------------------------------*/
/* USER CODE BEGIN ExternalFunctions */

/* USER CODE END ExternalFunctions */

/* USER CODE BEGIN 0 */

/* USER CODE END 0 */
/**
 * @brief Initializes the Global MSP.
 *
 * Configures the system-level hardware resources like the clock for the
 * System Configuration controller (SYSCFG).
 */
void HAL_MspInit(void) {

  /* USER CODE BEGIN MspInit 0 */

  /* USER CODE END MspInit 0 */

  __HAL_RCC_SYSCFG_CLK_ENABLE();

  /* System interrupt init*/

  /* USER CODE BEGIN MspInit 1 */

  /* USER CODE END MspInit 1 */
}

/**
 * @brief DCMI MSP Initialization
 *
 * Configures the hardware resources for the Digital Camera Interface:
 * - Enables peripheral and GPIO clocks.
 * - Configures the DCMI data (D0-D7), HSYNC, VSYNC, and PIXCLK pins.
 * - Configures and initializes the DMA stream (DMA1_Stream0).
 * - Enables the DCMI interrupt in the NVIC.
 *
 * @param hdcmi: DCMI handle pointer
 * @retval None
 */
void HAL_DCMI_MspInit(DCMI_HandleTypeDef *hdcmi) {
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if (hdcmi->Instance == DCMI) {
    /* USER CODE BEGIN DCMI_MspInit 0 */

    /* USER CODE END DCMI_MspInit 0 */
    /* Peripheral clock enable */
    __HAL_RCC_DCMI_CLK_ENABLE();

    __HAL_RCC_GPIOE_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOC_CLK_ENABLE();
    __HAL_RCC_GPIOD_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();
    /**DCMI GPIO Configuration
    PE6     ------> DCMI_D7
    PA4     ------> DCMI_HSYNC
    PA6     ------> DCMI_PIXCLK
    PC8     ------> DCMI_D2
    PC9     ------> DCMI_D3
    PA9     ------> DCMI_D0
    PA10     ------> DCMI_D1
    PC11     ------> DCMI_D4
    PD3     ------> DCMI_D5
    PB7     ------> DCMI_VSYNC
    PB8     ------> DCMI_D6
    */
    GPIO_InitStruct.Pin = GPIO_PIN_6;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF13_DCMI;
    HAL_GPIO_Init(GPIOE, &GPIO_InitStruct);

    GPIO_InitStruct.Pin = GPIO_PIN_4 | GPIO_PIN_6 | GPIO_PIN_9 | GPIO_PIN_10;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF13_DCMI;
    HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

    GPIO_InitStruct.Pin = GPIO_PIN_8 | GPIO_PIN_9 | GPIO_PIN_11;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF13_DCMI;
    HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

    GPIO_InitStruct.Pin = GPIO_PIN_3;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF13_DCMI;
    HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

    GPIO_InitStruct.Pin = GPIO_PIN_7 | GPIO_PIN_8;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF13_DCMI;
    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    HAL_I2CEx_EnableFastModePlus(SYSCFG_PMCR_I2C_PB8_FMP);

    /* DCMI DMA Init */
    /* DCMI Init */
    hdma_dcmi.Instance = DMA1_Stream0;
    hdma_dcmi.Init.Request = DMA_REQUEST_DCMI;
    hdma_dcmi.Init.Direction = DMA_PERIPH_TO_MEMORY;
    hdma_dcmi.Init.PeriphInc = DMA_PINC_DISABLE;
    hdma_dcmi.Init.MemInc = DMA_MINC_ENABLE;
    hdma_dcmi.Init.PeriphDataAlignment = DMA_PDATAALIGN_WORD;
    hdma_dcmi.Init.MemDataAlignment = DMA_MDATAALIGN_WORD;
    hdma_dcmi.Init.Mode = DMA_CIRCULAR;
    hdma_dcmi.Init.Priority = DMA_PRIORITY_HIGH;
    hdma_dcmi.Init.FIFOMode = DMA_FIFOMODE_ENABLE;
    hdma_dcmi.Init.FIFOThreshold = DMA_FIFO_THRESHOLD_FULL;
    hdma_dcmi.Init.MemBurst = DMA_MBURST_INC4;
    hdma_dcmi.Init.PeriphBurst = DMA_PBURST_SINGLE;
    if (HAL_DMA_Init(&hdma_dcmi) != HAL_OK) {
      Error_Handler();
    }

    __HAL_LINKDMA(hdcmi, DMA_Handle, hdma_dcmi);

    /* DCMI interrupt Init */
    HAL_NVIC_SetPriority(DCMI_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(DCMI_IRQn);
    /* USER CODE BEGIN DCMI_MspInit 1 */

    /* USER CODE END DCMI_MspInit 1 */
  }
}

/**
 * @brief DCMI MSP De-Initialization
 *
 * Releases the hardware resources used by the DCMI:
 * - Disables the DCMI peripheral clock.
 * - De-initializes the camera interface GPIO pins.
 * - De-initializes the DMA handle.
 * - Disables the DCMI interrupt in the NVIC.
 *
 * @param hdcmi: DCMI handle pointer
 * @retval None
 */
void HAL_DCMI_MspDeInit(DCMI_HandleTypeDef *hdcmi) {
  if (hdcmi->Instance == DCMI) {
    /* USER CODE BEGIN DCMI_MspDeInit 0 */

    /* USER CODE END DCMI_MspDeInit 0 */
    /* Peripheral clock disable */
    __HAL_RCC_DCMI_CLK_DISABLE();

    /**DCMI GPIO Configuration
    PE6     ------> DCMI_D7
    PA4     ------> DCMI_HSYNC
    PA6     ------> DCMI_PIXCLK
    PC8     ------> DCMI_D2
    PC9     ------> DCMI_D3
    PA9     ------> DCMI_D0
    PA10     ------> DCMI_D1
    PC11     ------> DCMI_D4
    PD3     ------> DCMI_D5
    PB7     ------> DCMI_VSYNC
    PB8     ------> DCMI_D6
    */
    HAL_GPIO_DeInit(GPIOE, GPIO_PIN_6);

    HAL_GPIO_DeInit(GPIOA, GPIO_PIN_4 | GPIO_PIN_6 | GPIO_PIN_9 | GPIO_PIN_10);

    HAL_GPIO_DeInit(GPIOC, GPIO_PIN_8 | GPIO_PIN_9 | GPIO_PIN_11);

    HAL_GPIO_DeInit(GPIOD, GPIO_PIN_3);

    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_7 | GPIO_PIN_8);

    /* DCMI DMA DeInit */
    HAL_DMA_DeInit(hdcmi->DMA_Handle);

    /* DCMI interrupt DeInit */
    HAL_NVIC_DisableIRQ(DCMI_IRQn);
    /* USER CODE BEGIN DCMI_MspDeInit 1 */

    /* USER CODE END DCMI_MspDeInit 1 */
  }
}

/**
 * @brief I2C MSP Initialization
 *
 * Configures the hardware resources for I2C1:
 * - Selects the I2C1 clock source (CSI).
 * - Enables the GPIO clock for I2C pins.
 * - Configures SCL (PB6) and SDA (PB9) as Open-Drain Alternate Functions.
 * - Enables the I2C1 peripheral clock.
 *
 * @param hi2c: I2C handle pointer
 * @retval None
 */
void HAL_I2C_MspInit(I2C_HandleTypeDef *hi2c) {
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  RCC_PeriphCLKInitTypeDef PeriphClkInitStruct = {0};
  if (hi2c->Instance == I2C1) {
    /* USER CODE BEGIN I2C1_MspInit 0 */

    /* USER CODE END I2C1_MspInit 0 */

    /** Initializes the peripherals clock
     */
    PeriphClkInitStruct.PeriphClockSelection = RCC_PERIPHCLK_I2C1;
    PeriphClkInitStruct.I2c123ClockSelection = RCC_I2C123CLKSOURCE_CSI;
    if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInitStruct) != HAL_OK) {
      Error_Handler();
    }

    __HAL_RCC_GPIOB_CLK_ENABLE();
    /**I2C1 GPIO Configuration
    PB6     ------> I2C1_SCL
    PB9     ------> I2C1_SDA
    */
    GPIO_InitStruct.Pin = GPIO_PIN_6 | GPIO_PIN_9;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_OD;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
    GPIO_InitStruct.Alternate = GPIO_AF4_I2C1;
    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    /* Peripheral clock enable */
    __HAL_RCC_I2C1_CLK_ENABLE();
    /* USER CODE BEGIN I2C1_MspInit 1 */

    /* USER CODE END I2C1_MspInit 1 */
  }
}

/**
 * @brief I2C MSP De-Initialization
 *
 * Releases the hardware resources used by I2C1:
 * - Disables the I2C1 peripheral clock.
 * - De-initializes the SCL and SDA GPIO pins.
 *
 * @param hi2c: I2C handle pointer
 * @retval None
 */
void HAL_I2C_MspDeInit(I2C_HandleTypeDef *hi2c) {
  if (hi2c->Instance == I2C1) {
    /* USER CODE BEGIN I2C1_MspDeInit 0 */

    /* USER CODE END I2C1_MspDeInit 0 */
    /* Peripheral clock disable */
    __HAL_RCC_I2C1_CLK_DISABLE();

    /**I2C1 GPIO Configuration
    PB6     ------> I2C1_SCL
    PB9     ------> I2C1_SDA
    */
    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_6);

    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_9);

    /* USER CODE BEGIN I2C1_MspDeInit 1 */

    /* USER CODE END I2C1_MspDeInit 1 */
  }
}

/* USER CODE BEGIN 1 */

/* USER CODE END 1 */

// all code written by me with minimal AI assistance, comments added using AI
// and verified by me