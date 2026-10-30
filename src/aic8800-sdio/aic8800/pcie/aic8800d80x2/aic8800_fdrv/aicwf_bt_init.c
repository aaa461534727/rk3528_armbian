#include "aicwf_pcie.h"
#include "rwnx_platform.h"
#include "aicwf_debug.h"
#include "rwnx_defs.h"

extern int testmode;

struct bt_patch_file_name bt_patch_name[] = {
    [PRODUCT_ID_AIC8800D80-PRODUCT_ID_AIC8800D80] = {
        .fw_adid           = FW_ADID_BASE_NAME_8800D80_U02,
        .fw_patch          = FW_PATCH_BASE_NAME_8800D80_U02,
        .fw_patch_table    = FW_PATCH_TABLE_NAME_8800D80_U02,
    },
    [PRODUCT_ID_AIC8800D80X2-PRODUCT_ID_AIC8800D80] = {
        .fw_adid           = FW_ADID_BASE_NAME_8800D80X2_U05,
        .fw_patch          = FW_PATCH_BASE_NAME_8800D80X2_U05,
        .fw_patch_table    = FW_PATCH_TABLE_NAME_8800D80X2_U05,
    },
};

int aicwf_bt_init(struct rwnx_hw *rwnx_hw){
    //u32 tmp = 0;
    //int err;

    struct aicbt_patch_table *head = NULL;
    struct aicbt_patch_info_t patch_info = {
        .info_len          = 0,
        .adid_addrinf      = 0,
        .addr_adid         = 0,
        .patch_addrinf     = 0,
        .addr_patch        = 0,
        .reset_addr        = 0,
        .reset_val         = 0,
        .adid_flag_addr    = 0,
        .adid_flag         = 0,
    };
    struct bt_patch_file_name *bt_patch_file = NULL;

    AICWFDBG(LOGINFO, "%s chip_id:%d\r\n", __func__, rwnx_hw->pcidev->chip_id);
    bt_patch_file = &bt_patch_name[rwnx_hw->pcidev->chip_id- PRODUCT_ID_AIC8800D80];
    
    head = aicbt_patch_table_alloc(rwnx_hw, bt_patch_file->fw_patch_table);
    if (head == NULL){
        AICWFDBG(LOGERROR, "aicbt_patch_table_alloc fail\n");
        return -1;
    }

    patch_info.addr_adid = FW_RAM_ADID_BASE_ADDR_8800D80_U02;
    patch_info.addr_patch = FW_RAM_PATCH_BASE_ADDR_8800D80_U02;

    aicbt_patch_info_unpack(&patch_info, head);
    if(patch_info.info_len == 0) {
        AICWFDBG(LOGERROR, "%s, aicbt_patch_info_unpack fail\n", __func__);
        return -1;
    }

    AICWFDBG(LOGINFO, "addr_adid 0x%x, addr_patch 0x%x\n", patch_info.addr_adid, patch_info.addr_patch);

	if(rwnx_plat_bin_fw_upload_2(rwnx_hw, patch_info.addr_adid, (char*)bt_patch_file->fw_adid)) {
		return -1;
	}

	if(rwnx_plat_bin_fw_upload_2(rwnx_hw, patch_info.addr_patch, (char*)bt_patch_file->fw_patch)) {
		return -1;
	}

    if (aicbt_patch_table_load(rwnx_hw, head)) {
        return -1;
    }

    //if(testmode == 0) {
    //     mdelay(30);
    //    while (!(tmp & (0x1 << 3))) {
    //        err = aicwf_pcie_tran(rwnx_hw->pcidev, (void *)0x40305084, &tmp, 4, AIC_TRAN_EMB2DRV, 1);
    //        msleep(1);
    //    }
    //} else
    mdelay(70);

    return 0;
}
