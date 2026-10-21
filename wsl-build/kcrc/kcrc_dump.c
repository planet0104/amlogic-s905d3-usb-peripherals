/*
 * kcrc_dump - 从 arm64 内核 Image 里提取导出符号的 MODVERSIONS CRC
 *
 * 用法（在板子上）：grep ' __kcrctab_' /proc/kallsyms | kcrc_dump Image > board-kernel.crc
 *
 * 4.9 的 arm64 内核开了 RELOCATABLE（KASLR）时，__kcrctab_<sym> 槽位在 Image 里是 0，
 * 真正的 CRC 存在 .rela.dyn 的 R_AARCH64_RELATIVE 条目的 addend 里，开机时才填进去。
 * 所以按 kallsyms 给出的槽位地址，在 Image 里找 r_offset 等于该地址的重定位条目。
 * 前提：内核运行时没有随机偏移（kallsyms 地址 = 链接地址），这块板子满足。
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define R_AARCH64_RELATIVE 0x403

struct slot {
	uint64_t addr;
	char name[128];
	int found;
	uint32_t crc;
};

static int by_addr(const void *a, const void *b)
{
	uint64_t x = ((const struct slot *)a)->addr, y = ((const struct slot *)b)->addr;
	return x < y ? -1 : x > y;
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: grep ' __kcrctab_' /proc/kallsyms | %s Image\n", argv[0]);
		return 1;
	}

	size_t n = 0, cap = 16384;
	struct slot *s = malloc(cap * sizeof(*s));
	char line[256], type[8], name[138];
	unsigned long long addr;
	while (fgets(line, sizeof(line), stdin)) {
		/* 模块导出的符号行尾带 [模块名]，不在 Image 里，跳过 */
		if (strchr(line, '[') || sscanf(line, "%llx %7s %137s", &addr, type, name) != 3)
			continue;
		if (strncmp(name, "__kcrctab_", 10))
			continue;
		if (n == cap)
			s = realloc(s, (cap *= 2) * sizeof(*s));
		s[n].addr = addr;
		snprintf(s[n].name, sizeof(s[n].name), "%s", name + 10);
		s[n].found = 0;
		n++;
	}
	if (!n) {
		fprintf(stderr, "no __kcrctab_ symbols on stdin\n");
		return 1;
	}
	qsort(s, n, sizeof(*s), by_addr);

	FILE *f = fopen(argv[1], "rb");
	if (!f) {
		perror(argv[1]);
		return 1;
	}
	fseek(f, 0, SEEK_END);
	long len = ftell(f);
	fseek(f, 0, SEEK_SET);
	uint8_t *b = malloc(len);
	if (!b || fread(b, 1, len, f) != (size_t)len) {
		perror("read");
		return 1;
	}

	for (long i = 0; i + 24 <= len; i += 8) {
		uint64_t off, info, add;
		memcpy(&info, b + i + 8, 8);
		if (info != R_AARCH64_RELATIVE)
			continue;
		memcpy(&off, b + i, 8);
		if (off < s[0].addr || off > s[n - 1].addr)
			continue;
		struct slot key = { .addr = off };
		struct slot *hit = bsearch(&key, s, n, sizeof(*s), by_addr);
		if (!hit)
			continue;
		memcpy(&add, b + i + 16, 8);
		hit->crc = (uint32_t)add;
		hit->found = 1;
	}

	size_t missing = 0;
	for (size_t i = 0; i < n; i++) {
		if (s[i].found)
			printf("0x%08x\t%s\n", s[i].crc, s[i].name);
		else
			missing++;
	}
	fprintf(stderr, "%zu symbols, %zu without CRC\n", n, missing);
	return missing ? 2 : 0;
}
