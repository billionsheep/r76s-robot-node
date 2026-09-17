R76S_EDGE_AGENT_VERSION = 0.1.0
# 引用仓库唯一源码；local 机制由 Buildroot 同步到包的构建目录。
R76S_EDGE_AGENT_SITE = $(BR2_EXTERNAL_R76S_LAB_PATH)/../../../edge-agent
R76S_EDGE_AGENT_SITE_METHOD = local

define R76S_EDGE_AGENT_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -Wall -Wextra \
		"$(@D)/main.c" -o "$(@D)/edge-agent" $(TARGET_LDFLAGS)
endef

define R76S_EDGE_AGENT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 "$(@D)/edge-agent" "$(TARGET_DIR)/usr/bin/edge-agent"
endef

$(eval $(generic-package))
