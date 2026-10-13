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

#if defined(__APPLE__) || defined(__linux__) || defined(__ANDROID__) || defined(__FreeBSD__)
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>
#endif

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

BBString * bmx_gamenet_enet_local_ipv4_address(void) {
#if defined(__APPLE__) || defined(__linux__) || defined(__ANDROID__) || defined(__FreeBSD__)
	struct ifaddrs * interfaces = NULL;
	struct ifaddrs * interface;
	char bestAddress[INET_ADDRSTRLEN] = { 0 };
	int bestScore = -1;

	if (getifaddrs(&interfaces) != 0) {
		return &bbEmptyString;
	}

	for (interface = interfaces; interface; interface = interface->ifa_next) {
		if (!interface->ifa_addr || interface->ifa_addr->sa_family != AF_INET) {
			continue;
		}
		if (!(interface->ifa_flags & IFF_UP) || (interface->ifa_flags & IFF_LOOPBACK)) {
			continue;
		}

		struct sockaddr_in * socketAddress = (struct sockaddr_in *) interface->ifa_addr;
		uint32_t address = ntohl(socketAddress->sin_addr.s_addr);
		if ((address >> 24) == 127 || (address >> 16) == 0xa9fe) {
			continue;
		}

		int isPrivate =
			(address >> 24) == 10 ||
			(address >> 20) == 0xac1 ||
			(address >> 16) == 0xc0a8;
		int score = isPrivate ? 20 : 10;
		if (strcmp(interface->ifa_name, "en0") == 0 ||
			strcmp(interface->ifa_name, "wlan0") == 0) {
			score += 20;
		}
		if (score <= bestScore) {
			continue;
		}

		if (inet_ntop(AF_INET, &socketAddress->sin_addr, bestAddress, sizeof(bestAddress))) {
			bestScore = score;
		}
	}

	freeifaddrs(interfaces);
	if (bestScore >= 0) {
		return bbStringFromUTF8String((const unsigned char *) bestAddress);
	}
#endif
	return &bbEmptyString;
}
