#include "kernels.h"
#include "linalg.h"
#include "state.cuh"
#include <cstdio>
#include <vector>

// For deformation gradient update

// Takes B, dL/dAB
// Returns dL/dA
__device__ Matrix dAB2dA(const Matrix &B, const Matrix &dAB) {
  Matrix dA;
  for (int p = 0; p < dim; p++) {
    for (int q = 0; q < dim; q++) {
      for (int j = 0; j < dim; j++) {
        dA[p][q] += dAB[p][j] * B[q][j];
      }
    }
  }
  return dA;
}

// Takes A, B, dL/dAB
// Returns dL/dB
__device__ Matrix dAB2dB(const Matrix &A, const Matrix &dAB) {
  Matrix dB;
  for (int p = 0; p < dim; p++) {
    for (int q = 0; q < dim; q++) {
      for (int i = 0; i < dim; i++) {
        dB[p][q] += dAB[i][q] * A[i][p];
      }
    }
  }
  return dB;
}

__device__ Vector duTv2du(const Vector &v, const real &duTv) {
  return duTv * v;
}

__device__ Vector duTv2dv(const Vector &u, const real &duTv) {
  return duTv * u;
}

TC_FORCE_INLINE __device__ real Clamp_Small_Magnitude(const real input) {
  real magnitude = input > 0 ? input : -input;
  real sign = input > 0 ? 1.f : -1.f;
  real output = magnitude > 1e-6 ? magnitude : 1e-6;
  return output * sign;
}

__device__ void Times_Rotated_dP_dF_FixedCorotated(const real mu,
                                                   const real lambda,
                                                   const real *F,
                                                   const real *d_SVD,
                                                   const int parid,
                                                   const real *dF,
                                                   real *dP) {
  real U[9];
  real S[3];
  real V[9];
#ifdef LOAD_SVD
  U[0] = d_SVD[parid * 21 + 0];
  U[1] = d_SVD[parid * 21 + 1];
  U[2] = d_SVD[parid * 21 + 2];
  U[3] = d_SVD[parid * 21 + 3];
  U[4] = d_SVD[parid * 21 + 4];
  U[5] = d_SVD[parid * 21 + 5];
  U[6] = d_SVD[parid * 21 + 6];
  U[7] = d_SVD[parid * 21 + 7];
  U[8] = d_SVD[parid * 21 + 8];

  S[0] = d_SVD[parid * 21 + 9];
  S[1] = d_SVD[parid * 21 + 10];
  S[2] = d_SVD[parid * 21 + 11];

  V[0] = d_SVD[parid * 21 + 12];
  V[1] = d_SVD[parid * 21 + 13];
  V[2] = d_SVD[parid * 21 + 14];
  V[3] = d_SVD[parid * 21 + 15];
  V[4] = d_SVD[parid * 21 + 16];
  V[5] = d_SVD[parid * 21 + 17];
  V[6] = d_SVD[parid * 21 + 18];
  V[7] = d_SVD[parid * 21 + 19];
  V[8] = d_SVD[parid * 21 + 20];
#else
  svd(F[0], F[3], F[6], F[1], F[4], F[7], F[2], F[5], F[8], U[0], U[3], U[6],
      U[1], U[4], U[7], U[2], U[5], U[8], S[0], S[1], S[2], V[0], V[3], V[6],
      V[1], V[4], V[7], V[2], V[5], V[8]);
#endif

  //
  real J = S[0] * S[1] * S[2];
  real scaled_mu = 2.f * mu;
  real scaled_lambda = lambda * (J - 1.f);
  real P_hat[3];
  P_hat[0] = scaled_mu * (S[0] - 1.f) + scaled_lambda * (S[1] * S[2]);
  P_hat[1] = scaled_mu * (S[1] - 1.f) + scaled_lambda * (S[0] * S[2]);
  P_hat[2] = scaled_mu * (S[2] - 1.f) + scaled_lambda * (S[0] * S[1]);

  real dP_hat_dSigma_upper[6];
  scaled_lambda = lambda * (2.f * J - 1.f) * J;
  for (int i = 0; i < 3; ++i)
    dP_hat_dSigma_upper[i] = scaled_mu + lambda * J * J / (S[i] * S[i]);
  dP_hat_dSigma_upper[3] = scaled_lambda / (S[0] * S[1]);
  dP_hat_dSigma_upper[4] = scaled_lambda / (S[0] * S[2]);
  dP_hat_dSigma_upper[5] = scaled_lambda / (S[1] * S[2]);

  scaled_lambda = -lambda * (J - 1.f) * J;
  real M[3];
  M[0] = 0.5f * (2.f * mu + scaled_lambda / (S[0] * S[1]));
  M[1] = 0.5f * (2.f * mu + scaled_lambda / (S[0] * S[2]));
  M[2] = 0.5f * (2.f * mu + scaled_lambda / (S[2] * S[2]));
  //

  real P[3];
  P[0] = 0.5 * (P_hat[0] + P_hat[1]) / Clamp_Small_Magnitude(S[0] + S[1]);
  P[1] = 0.5 * (P_hat[0] + P_hat[2]) / Clamp_Small_Magnitude(S[0] + S[2]);
  P[2] = 0.5 * (P_hat[1] + P_hat[2]) / Clamp_Small_Magnitude(S[1] + S[2]);

  real dF_hat[9];
  dF_hat[0] = (dF[0] * U[0] + dF[1] * U[1] + dF[2] * U[2]) * V[0] +
              (dF[3] * U[0] + dF[4] * U[1] + dF[5] * U[2]) * V[1] +
              (dF[6] * U[0] + dF[7] * U[1] + dF[8] * U[2]) * V[2];
  dF_hat[1] = (dF[0] * U[3] + dF[1] * U[4] + dF[2] * U[5]) * V[0] +
              (dF[3] * U[3] + dF[4] * U[4] + dF[5] * U[5]) * V[1] +
              (dF[6] * U[3] + dF[7] * U[4] + dF[8] * U[5]) * V[2];
  dF_hat[2] = (dF[0] * U[6] + dF[1] * U[7] + dF[2] * U[8]) * V[0] +
              (dF[3] * U[6] + dF[4] * U[7] + dF[5] * U[8]) * V[1] +
              (dF[6] * U[6] + dF[7] * U[7] + dF[8] * U[8]) * V[2];
  dF_hat[3] = (dF[0] * U[0] + dF[1] * U[1] + dF[2] * U[2]) * V[3] +
              (dF[3] * U[0] + dF[4] * U[1] + dF[5] * U[2]) * V[4] +
              (dF[6] * U[0] + dF[7] * U[1] + dF[8] * U[2]) * V[5];
  dF_hat[4] = (dF[0] * U[3] + dF[1] * U[4] + dF[2] * U[5]) * V[3] +
              (dF[3] * U[3] + dF[4] * U[4] + dF[5] * U[5]) * V[4] +
              (dF[6] * U[3] + dF[7] * U[4] + dF[8] * U[5]) * V[5];
  dF_hat[5] = (dF[0] * U[6] + dF[1] * U[7] + dF[2] * U[8]) * V[3] +
              (dF[3] * U[6] + dF[4] * U[7] + dF[5] * U[8]) * V[4] +
              (dF[6] * U[6] + dF[7] * U[7] + dF[8] * U[8]) * V[5];
  dF_hat[6] = (dF[0] * U[0] + dF[1] * U[1] + dF[2] * U[2]) * V[6] +
              (dF[3] * U[0] + dF[4] * U[1] + dF[5] * U[2]) * V[7] +
              (dF[6] * U[0] + dF[7] * U[1] + dF[8] * U[2]) * V[8];
  dF_hat[7] = (dF[0] * U[3] + dF[1] * U[4] + dF[2] * U[5]) * V[6] +
              (dF[3] * U[3] + dF[4] * U[4] + dF[5] * U[5]) * V[7] +
              (dF[6] * U[3] + dF[7] * U[4] + dF[8] * U[5]) * V[8];
  dF_hat[8] = (dF[0] * U[6] + dF[1] * U[7] + dF[2] * U[8]) * V[6] +
              (dF[3] * U[6] + dF[4] * U[7] + dF[5] * U[8]) * V[7] +
              (dF[6] * U[6] + dF[7] * U[7] + dF[8] * U[8]) * V[8];

  real dP_hat[9];
  dP_hat[0] = dP_hat_dSigma_upper[0] * dF_hat[0] +
              dP_hat_dSigma_upper[3] * dF_hat[4] +
              dP_hat_dSigma_upper[4] * dF_hat[8];
  dP_hat[4] = dP_hat_dSigma_upper[3] * dF_hat[0] +
              dP_hat_dSigma_upper[1] * dF_hat[4] +
              dP_hat_dSigma_upper[5] * dF_hat[8];
  dP_hat[8] = dP_hat_dSigma_upper[4] * dF_hat[0] +
              dP_hat_dSigma_upper[5] * dF_hat[4] +
              dP_hat_dSigma_upper[2] * dF_hat[8];
  dP_hat[3] = ((M[0] + P[0]) * dF_hat[3] + (M[0] - P[0]) * dF_hat[1]);
  dP_hat[1] = ((M[0] - P[0]) * dF_hat[3] + (M[0] + P[0]) * dF_hat[1]);
  dP_hat[6] = ((M[1] + P[1]) * dF_hat[6] + (M[1] - P[1]) * dF_hat[2]);
  dP_hat[2] = ((M[1] - P[1]) * dF_hat[6] + (M[1] + P[1]) * dF_hat[2]);
  dP_hat[7] = ((M[2] + P[2]) * dF_hat[7] + (M[2] - P[2]) * dF_hat[5]);
  dP_hat[5] = ((M[2] - P[2]) * dF_hat[7] + (M[2] + P[2]) * dF_hat[5]);

  dP[0] = (dP_hat[0] * U[0] + dP_hat[1] * U[3] + dP_hat[2] * U[6]) * V[0] +
          (dP_hat[3] * U[0] + dP_hat[4] * U[3] + dP_hat[5] * U[6]) * V[3] +
          (dP_hat[6] * U[0] + dP_hat[7] * U[3] + dP_hat[8] * U[6]) * V[6];
  dP[1] = (dP_hat[0] * U[1] + dP_hat[1] * U[4] + dP_hat[2] * U[7]) * V[0] +
          (dP_hat[3] * U[1] + dP_hat[4] * U[4] + dP_hat[5] * U[7]) * V[3] +
          (dP_hat[6] * U[1] + dP_hat[7] * U[4] + dP_hat[8] * U[7]) * V[6];
  dP[2] = (dP_hat[0] * U[2] + dP_hat[1] * U[5] + dP_hat[2] * U[8]) * V[0] +
          (dP_hat[3] * U[2] + dP_hat[4] * U[5] + dP_hat[5] * U[8]) * V[3] +
          (dP_hat[6] * U[2] + dP_hat[7] * U[5] + dP_hat[8] * U[8]) * V[6];
  dP[3] = (dP_hat[0] * U[0] + dP_hat[1] * U[3] + dP_hat[2] * U[6]) * V[1] +
          (dP_hat[3] * U[0] + dP_hat[4] * U[3] + dP_hat[5] * U[6]) * V[4] +
          (dP_hat[6] * U[0] + dP_hat[7] * U[3] + dP_hat[8] * U[6]) * V[7];
  dP[4] = (dP_hat[0] * U[1] + dP_hat[1] * U[4] + dP_hat[2] * U[7]) * V[1] +
          (dP_hat[3] * U[1] + dP_hat[4] * U[4] + dP_hat[5] * U[7]) * V[4] +
          (dP_hat[6] * U[1] + dP_hat[7] * U[4] + dP_hat[8] * U[7]) * V[7];
  dP[5] = (dP_hat[0] * U[2] + dP_hat[1] * U[5] + dP_hat[2] * U[8]) * V[1] +
          (dP_hat[3] * U[2] + dP_hat[4] * U[5] + dP_hat[5] * U[8]) * V[4] +
          (dP_hat[6] * U[2] + dP_hat[7] * U[5] + dP_hat[8] * U[8]) * V[7];
  dP[6] = (dP_hat[0] * U[0] + dP_hat[1] * U[3] + dP_hat[2] * U[6]) * V[2] +
          (dP_hat[3] * U[0] + dP_hat[4] * U[3] + dP_hat[5] * U[6]) * V[5] +
          (dP_hat[6] * U[0] + dP_hat[7] * U[3] + dP_hat[8] * U[6]) * V[8];
  dP[7] = (dP_hat[0] * U[1] + dP_hat[1] * U[4] + dP_hat[2] * U[7]) * V[2] +
          (dP_hat[3] * U[1] + dP_hat[4] * U[4] + dP_hat[5] * U[7]) * V[5] +
          (dP_hat[6] * U[1] + dP_hat[7] * U[4] + dP_hat[8] * U[7]) * V[8];
  dP[8] = (dP_hat[0] * U[2] + dP_hat[1] * U[5] + dP_hat[2] * U[8]) * V[2] +
          (dP_hat[3] * U[2] + dP_hat[4] * U[5] + dP_hat[5] * U[8]) * V[5] +
          (dP_hat[6] * U[2] + dP_hat[7] * U[5] + dP_hat[8] * U[8]) * V[8];
};

// Constitutive models
/*
__device__ Matrix dP2dF_fixed_corotated(const Matrix &R,
                                        const Matrix &F,
                                        const Matrix &dF) {
  //Matrix dR, dS dS = dF * transposed(R) +
  //                   F * transposed(dR) return std::make_pair(dR, dS);
}
*/

//
__device__ void G2P_backtrace(State state, State next_state) {
  // Scatter particle gradients to grid nodes
  // G2P part of back-propagation

  int part_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (part_id >= state.num_particles) {
    return;
  }

  Vector x = state.get_x(part_id), v = state.get_v(part_id);
  Matrix F = state.get_F(part_id);
  Matrix C = state.get_C(part_id);

  auto grad_x = next_state.get_grad_x(part_id);
  auto grad_C_next = next_state.get_grad_C(part_id);
  auto grad_v_next = next_state.get_grad_v(part_id);
  Matrix G;  // TODO

  TransferCommon<true> tc(state, x);

  // Fixed corotated

  Matrix grad_C;

  for (int i = 0; i < dim; i++) {
    for (int j = 0; j < dim; j++) {
      for (int k = 0; k < dim; k++) {
        Vector vi, grad_p;  // TODO
        real mi;            // TODO
        real grad_mi = 0;   // TODO
        Vector dpos = tc.dpos(i, j, k);

        real contrib[dim + 1];

        auto grad_N = tc.dw(i, j, k);

        for (int alpha = 0; alpha < dim; alpha++) {
          grad_x[alpha] +=
              grad_N[alpha] * (grad_v_next[alpha] * state.invD +
                               grad_p[alpha] * mi * vi[alpha] + m_p * grad_mi);
          for (int beta = 0; beta < dim; beta++) {
            grad_x[alpha] += state.invD * grad_C_next[beta][alpha] *
                                 (grad_N[alpha] * vi[alpha] * dpos[beta] -
                                  tc.w(i, j, k) * vi[alpha]) -
                             grad_p[beta] * G[beta][alpha];
            grad_C[alpha][beta] += grad_p[alpha] * m_p * (dpos[beta]);
          }
        }
      }
    }
  }

  state.set_x(part_id, grad_x);
  auto grad_F_next = next_state.get_grad_F(part_id);
  Matrix grad_F;
  for (int alpha = 0; alpha < dim; alpha++) {
    for (int beta = 0; beta < dim; beta++) {
      for (int gamma = 0; gamma < dim; gamma++) {
        grad_F[alpha][beta];
      }
    }
  }
}

__device__ void grid_backtrace(State state, State next_state) {
  // Scatter particle gradients to grid nodes
  // P2G part of back-propagation
  int id = blockIdx.x * blockDim.x + threadIdx.x;
  int boundary = 3;
  if (id < state.num_cells) {
    auto node = state.grid_node(id);
    if (node[dim] > 0) {
      real inv_m = 1.0f / node[dim];
      node[0] *= inv_m;
      node[1] *= inv_m;
      node[2] *= inv_m;
      for (int i = 0; i < dim; i++) {
        node[i] += state.gravity[i] * state.dt;
      }
      int x = id / (state.res[1] * state.res[2]),
          y = id / state.res[2] % state.res[1], z = id % state.res[2];
    }
  }
}

__device__ void P2G_backtrace(State state, State next_state) {
  // Scatter particle gradients to grid nodes
  // P2G part of back-propagation
  int part_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (part_id >= state.num_particles) {
    return;
  }

  // Convert grad_v to grad_p
  // grad_p = grad_v / m

}

__global__ void backtrace(State &current, State &next) {
}