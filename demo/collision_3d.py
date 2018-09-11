import sys
sys.path.append('..')

import random
import time
from simulation import Simulation, get_bounding_box_bc
import tensorflow as tf
import numpy as np
from IPython import embed

batch_size = 1
gravity = (0, 0)
N = 5
group_particles = N * N * N
num_balls = 2
num_particles = group_particles * num_balls
steps = 100
dt = 1e-2
res = (100, 100, 100)
bc = get_bounding_box_bc(res)

lr = 2e1


def main(sess):
  
  goal = tf.placeholder(dtype=tf.float32, shape=[batch_size, 3], name='goal')

  sim = Simulation(
      dt=dt,
      num_particles=num_particles,
      grid_res=res,
      bc=bc,
      gravity=gravity,
      sess=sess)
  position = np.zeros(shape=(batch_size, 3, num_particles))
  velocity_delta = np.zeros(shape=(batch_size, 3, num_particles))
  
  F = np.zeros(shape=(batch_size, 3, 3, num_particles))
  scale = 1.05
  F[:, 0, 0, :] = scale
  F[:, 1, 1, :] = scale
  F[:, 2, 2, :] = scale

  #velocity_ph = tf.Variable([0.4, 0.00, 0.0], trainable = True)
  delta = np.zeros(shape=(batch_size, 3, group_particles), dtype=np.float32)
  delta[:, 0, :] = 0.1
  velocity_ph = tf.Variable(delta, trainable=True)
  velocity_1 = velocity_ph + delta
  if num_balls > 1:
    velocity_2 = tf.zeros(shape=[batch_size, 3, group_particles], dtype=tf.float32)
    velocity = tf.concat([velocity_1, velocity_2], axis=2)
  else:
    velocity = velocity_1

  for b in range(batch_size):
    for i in range(group_particles):
      x, y, z = 0, 0, 0
      while (x - 0.5) ** 2 + (y - 0.5) ** 2 + (z - 0.5) ** 2 > 0.25:
        x, y, z = random.random(), random.random(), random.random()
      position[b, :, i] = ((x * 2 - 1) / 30 + 0.2,
                        (y * 2 - 1) / 30 + 0.4, (z * 2 - 1) / 30 + 0.4)
      velocity_delta[b, :, i] = (y - 0.5, -x + 0.5, 0)

    if num_balls > 1:
      for i in range(group_particles):
        x, y, z = 0, 0, 0
        while (x - 0.5) ** 2 + (y - 0.5) ** 2 + (z - 0.5) ** 2 > 0.25:
          x, y, z = random.random(), random.random(), random.random()
        position[b, :, i + group_particles] = ((x * 2 - 1) / 30 + 0.4,
                                            (y * 2 - 1) / 30 + 0.4, (z * 2 - 1) / 30 + 0.4)
        
  velocity += velocity_delta

  sess.run(tf.global_variables_initializer())

  initial_state = sim.get_initial_state(
      position=position, velocity=velocity, deformation_gradient=F)

  if num_balls == 2:
    final_position = sim.initial_state.center_of_mass(group_particles, None)
  else:
    final_position = sim.initial_state.center_of_mass(None, group_particles)
  loss = tf.reduce_sum((final_position - goal) ** 2)

  trainables = tf.get_collection(tf.GraphKeys.TRAINABLE_VARIABLES)
  sim.set_initial_state(initial_state = initial_state)

  sym = sim.gradients_sym(loss, variables = trainables)

  goal_input = np.array([[0.6, 0.43, 0.4]], dtype=np.float32)

  for i in range(1000000):
    t = time.time()
    memo = sim.run(
        initial_state = initial_state, 
        num_steps = steps,
        iteration_feed_dict = {goal: goal_input},
        loss = loss)
    grad = sim.eval_gradients(sym, memo)
    print('grad', grad[0])
    gradient_descent = [
        v.assign(v - lr * g) for v, g in zip(trainables, grad)
    ]
    print(sess.run(velocity_ph))
    sess.run(gradient_descent)
    print('iter {:5d} time {:.3f} loss {:.4f}'.format(
        i, time.time() - t, memo.loss))
    if i % 5 == 0: # True: # memo.loss < 0.01: 
      sim.visualize(memo)
    
if __name__ == '__main__':
  sess_config = tf.ConfigProto(allow_soft_placement=True)
  sess_config.gpu_options.allow_growth = True
  sess_config.gpu_options.per_process_gpu_memory_fraction = 0.4

  with tf.Session(config=sess_config) as sess:
    main(sess=sess)
