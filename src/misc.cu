#include "kernels.h"
#include "linalg.h"
#include "state.cuh"
#include <cstdio>
#include <vector>

__global__ void saxpy(int n, real a, real *x, real *y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    y[i] = a * x[i] + y[i];
  }
}

void saxpy_cuda(int N, real alpha, real *x, real *y) {
  real *d_x, *d_y;

  cudaMalloc(&d_x, N * sizeof(real));
  cudaMalloc(&d_y, N * sizeof(real));

  cudaMemcpy(d_x, x, N * sizeof(real), cudaMemcpyHostToDevice);
  cudaMemcpy(d_y, y, N * sizeof(real), cudaMemcpyHostToDevice);

  saxpy<<<(N + 255) / 256, 256>>>(N, alpha, d_x, d_y);

  cudaMemcpy(y, d_y, N * sizeof(real), cudaMemcpyDeviceToHost);

  cudaFree(d_x);
  cudaFree(d_y);
}

__global__ void test_svd(int n, Matrix *A, Matrix *U, Matrix *sig, Matrix *V) {
  int id = blockIdx.x * blockDim.x + threadIdx.x;
  if (id < n) {
    svd(A[id], U[id], sig[id], V[id]);
  }
}

// 3D only..
void test_svd_cuda(int n, real *A, real *U, real *sig, real *V) {
  Matrix *d_A, *d_U, *d_sig, *d_V;

  cudaMalloc(&d_A, sizeof(Matrix) * (unsigned int)(n));
  cudaMemcpy(d_A, A, sizeof(Matrix) * n, cudaMemcpyHostToDevice);

  cudaMalloc(&d_U, sizeof(Matrix) * (unsigned int)(n));
  cudaMalloc(&d_sig, sizeof(Matrix) * (unsigned int)(n));
  cudaMalloc(&d_V, sizeof(Matrix) * (unsigned int)(n));

  test_svd<<<(n + 127) / 128, 128>>>(n, d_A, d_U, d_sig, d_V);

  std::vector<Matrix> h_U(n), h_sig(n), h_V(n);
  cudaMemcpy(h_U.data(), d_U, sizeof(Matrix) * n, cudaMemcpyDeviceToHost);
  cudaMemcpy(h_sig.data(), d_sig, sizeof(Matrix) * n, cudaMemcpyDeviceToHost);
  cudaMemcpy(h_V.data(), d_V, sizeof(Matrix) * n, cudaMemcpyDeviceToHost);

  // Taichi uses column-first storage
  for (int p = 0; p < n; p++) {
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        U[p * 12 + 4 * i + j] = h_U[p][j][i];
        sig[p * 12 + 4 * i + j] = h_sig[p][j][i];
        V[p * 12 + 4 * i + j] = h_V[p][j][i];
      }
    }
  }
}
