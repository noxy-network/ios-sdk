#ifndef NOXY_KYBER_H
#define NOXY_KYBER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NOXY_KYBER_PK_BYTES  1184
#define NOXY_KYBER_SK_BYTES  2400
#define NOXY_KYBER_CT_BYTES  1088
#define NOXY_KYBER_SS_BYTES  32

int noxy_kyber_keypair(uint8_t *pk, uint8_t *sk);
int noxy_kyber_encapsulate(uint8_t *ct, uint8_t *ss, const uint8_t *pk);
int noxy_kyber_decapsulate(uint8_t *ss, const uint8_t *ct, const uint8_t *sk);

#ifdef __cplusplus
}
#endif

#endif /* NOXY_KYBER_H */
