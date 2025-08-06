# Tasks and Jobs

For any given Game Engine, a key part of functionality is the ability to write and implement custom procedures to affect gameplay. As an ECS-based engine,
Milk utilizes systems to perform operations over the data within the ECS World. In order to run these systems, however, Milk exposes two methods: Tasks &
Jobs.

## Similarities

Despite being for different purposes at runtime, both Tasks & Jobs utilize the `Task` type under the hood. This grants a degree of freedom as a procedure designed
for a Task can be included as part of a Job, and vice versa. The `Task` type consists of a few key components: a `typeid` corresponding to a marker struct
representing the `Task`'s unique name, and an array of `System`s. When a `Task` is run, each `System` in the `Task`'s array is run in sequence in the order
of the array. For both Tasks and Jobs, a given `Task` is run on only one given Worker thread at a time, and is inaccessible to other Workers.

## Differences

While both Tasks and Jobs use a `Task` under the hood, the key difference lies in their use-case. Tasks are specialized for behavior designed to run
consistently at a given interval, for example physics Tasks which run each update frame (by default 60 FPS) and draw Tasks which run every real frame (as
fast as the computer can render). Tasks are confined entirely to a list contained within the current Scene, which is sliced by the Worker Pool in order
to divide and run each Task among the Workers. Tasks are assumed to finish within a given frame, as such a frame cannot finish until the tasks that need
to run have been entirely finished (corresponding to the slice of tasks being empty and the tasks in progress equalling zero).

Jobs, on the other hand, are specialized for one-time behavior. A given Job does not persist between frames, instead each time a Job is desired to be run
it must be `dispatch`ed. Whereas Tasks are delegated by the main thread to the Worker threads, any Main or Worker thread can dispatch a Job, and any Worker
thread can run a Job. Jobs are stored separately inside the Worker Pool, being contained within a dynamic array that actually grows and shrinks as Jobs are
dispatched. As a result, it's best practice that if you're dispatching the same Job repeatedly, you should likely convert the Job to a Task. Unlike Tasks,
Jobs can persist between frames, allowing a particularly long job to continue its work even if the thread which requested it has moved onto the next frame.
This behavior is ideal for functionality such as Asset loading and shader compilation, preventing stutters common to most games.