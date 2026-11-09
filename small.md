A large, randomly initialized network contains small subnetworks called "winning tickets". Trained on their own, they can match the full network's accuracy.
• The catch:
A winning ticket isn't just the right connections. It's also their original starting weights. Keep the same structure but re-randomize the weights, and performance drops.
• How to find one:
1 Save the network's initial weights
Train the full network
Prune a percentage of the smallest weights
Reset the remaining weights to their saved initial values
Repeat until you reach the size you want
I The results:
On MNIST (fully connected networks) and CIFAR-10 (convolutional networks), they found tickets just 10-20% of the original size, or even smaller, with matching accuracy. Tickets above a certain size even learned faster and reached higher test accuracy.