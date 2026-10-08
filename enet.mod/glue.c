/*
 Copyright (c) 2026 Bruce A Henderson and contributors

 This software is provided 'as-is', without any express or implied warranty.
 In no event will the authors be held liable for any damages arising from the
 use of this software.

 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the zlib/libpng license.
*/

#include <stdlib.h>

#include "pub.mod/enet.mod/enet/include/enet.h"
#include "brl.mod/blitz.mod/blitz.h"

ENetAddress * bmx_gamenet_enet_address_create(BBString * host, int port) {
	ENetAddress * address = (ENetAddress *) calloc(1, sizeof(ENetAddress));
	if (!address) {
		return NULL;
	}

	unsigned char * text = bbStringToUTF8String(host);
	int result = enet_address_set_host(address, (const char *) text);
	bbMemFree(text);

	if (result < 0) {
		free(address);
		return NULL;
	}

	address->port = (enet_uint16) port;
	return address;
}
