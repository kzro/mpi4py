#ifndef PyMPI_CONFIG_MPICH2_H
#define PyMPI_CONFIG_MPICH2_H

#ifdef MS_WINDOWS
#if !defined(MPICH2_NUMVERSION) || (MPICH2_NUMVERSION < 10100000)
#define PyMPI_MISSING_MPI_TYPE_CREATE_F90_INTEGER 1
#define PyMPI_MISSING_MPI_TYPE_CREATE_F90_REAL 1
#define PyMPI_MISSING_MPI_TYPE_CREATE_F90_COMPLEX 1
#endif /* MPICH2 < 1.1.0 */
#endif /* MS_WINDOWS */

#ifndef ROMIO_VERSION
#include "mpich2io.h"
#endif /* !ROMIO_VERSION */

#endif /* !PyMPI_CONFIG_MPICH2_H */
