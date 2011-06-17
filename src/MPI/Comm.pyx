# Communicator Comparisons
# ------------------------

IDENT     = MPI_IDENT     #: Groups are identical, contexts are the same
CONGRUENT = MPI_CONGRUENT #: Groups are identical, contexts are different
SIMILAR   = MPI_SIMILAR   #: Groups are similar, rank order differs
UNEQUAL   = MPI_UNEQUAL   #: Groups are different


# Communicator Topologies
# -----------------------

CART       = MPI_CART       #: Cartesian topology
GRAPH      = MPI_GRAPH      #: General graph topology
DIST_GRAPH = MPI_DIST_GRAPH #: Distributed graph topology


cdef class Comm:

    """
    Communicator
    """

    def __cinit__(self, Comm comm=None):
        self.ob_mpi = MPI_COMM_NULL
        if comm is not None:
            self.ob_mpi = comm.ob_mpi

    def __dealloc__(self):
        if not (self.flags & PyMPI_OWNED): return
        CHKERR( del_Comm(&self.ob_mpi) )

    def __richcmp__(self, other, int op):
        if not isinstance(self,  Comm): return NotImplemented
        if not isinstance(other, Comm): return NotImplemented
        cdef Comm s = <Comm>self, o = <Comm>other
        if   op == Py_EQ: return (s.ob_mpi == o.ob_mpi)
        elif op == Py_NE: return (s.ob_mpi != o.ob_mpi)
        else: raise TypeError("only '==' and '!='")

    def __bool__(self):
        return self.ob_mpi != MPI_COMM_NULL

    # Group
    # -----

    def Get_group(self):
        """
        Access the group associated with a communicator
        """
        cdef Group group = <Group>Group.__new__(Group)
        CHKERR( MPI_Comm_group(self.ob_mpi, &group.ob_mpi) )
        return group

    property group:
        """communicator group"""
        def __get__(self):
            return self.Get_group()

    # Communicator Accessors
    # ----------------------

    def Get_size(self):
        """
        Return the number of processes in a communicator
        """
        cdef int size = -1
        CHKERR( MPI_Comm_size(self.ob_mpi, &size) )
        return size

    property size:
        """number of processes in communicator"""
        def __get__(self):
            return self.Get_size()

    def Get_rank(self):
        """
        Return the rank of this process in a communicator
        """
        cdef int rank = MPI_PROC_NULL
        CHKERR( MPI_Comm_rank(self.ob_mpi, &rank) )
        return rank

    property rank:
        """rank of this process in communicator"""
        def __get__(self):
            return self.Get_rank()

    @classmethod
    def Compare(cls, Comm comm1 not None, Comm comm2 not None):
        """
        Compare two communicators
        """
        cdef int flag = MPI_UNEQUAL
        CHKERR( MPI_Comm_compare(comm1.ob_mpi, comm2.ob_mpi, &flag) )
        return flag

    # Communicator Constructors
    # -------------------------

    def Clone(self):
        """
        Clone an existing communicator
        """
        cdef Comm comm = <Comm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(self.ob_mpi, &comm.ob_mpi) )
        return comm

    # Communicator Destructor
    # -----------------------

    def Free(self):
        """
        Free a communicator
        """
        with nogil: CHKERR( MPI_Comm_free(&self.ob_mpi) )

    # Point to Point communication
    # ----------------------------

    # Blocking Send and Receive Operations
    # ------------------------------------

    def Send(self, buf, int dest=0, int tag=0):
        """
        Blocking send

        .. note:: This function may block until the message is
           received. Whether or not `Send` blocks depends on
           several factors and is implementation dependent
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        with nogil: CHKERR( MPI_Send(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi) )

    def Recv(self, buf, int source=0, int tag=0, Status status=None):
        """
        Blocking receive

        .. note:: This function blocks until the message is received
        """
        cdef _p_msg_p2p rmsg = message_p2p_recv(buf, source)
        cdef MPI_Status *statusp = arg_Status(status)
        with nogil: CHKERR( MPI_Recv(
            rmsg.buf, rmsg.count, rmsg.dtype,
            source, tag, self.ob_mpi, statusp) )

    # Send-Receive
    # ------------

    def Sendrecv(self, sendbuf, int dest=0, int sendtag=0,
                 recvbuf=None, int source=0, int recvtag=0,
                 Status status=None):
        """
        Send and receive a message

        .. note:: This function is guaranteed not to deadlock in
           situations where pairs of blocking sends and receives may
           deadlock.

        .. caution:: A common mistake when using this function is to
           mismatch the tags with the source and destination ranks,
           which can result in deadlock.
        """
        cdef _p_msg_p2p smsg = message_p2p_send(sendbuf, dest)
        cdef _p_msg_p2p rmsg = message_p2p_recv(recvbuf, source)
        cdef MPI_Status *statusp = arg_Status(status)
        with nogil: CHKERR( MPI_Sendrecv(
            smsg.buf, smsg.count, smsg.dtype, dest,   sendtag,
            rmsg.buf, rmsg.count, rmsg.dtype, source, recvtag,
            self.ob_mpi, statusp) )

    def Sendrecv_replace(self, buf,
                         int dest=0,  int sendtag=0,
                         int source=0, int recvtag=0,
                         Status status=None):
        """
        Send and receive a message

        .. note:: This function is guaranteed not to deadlock in
           situations where pairs of blocking sends and receives may
           deadlock.

        .. caution:: A common mistake when using this function is to
           mismatch the tags with the source and destination ranks,
           which can result in deadlock.
        """
        cdef int rank = MPI_PROC_NULL
        if dest   != MPI_PROC_NULL: rank = dest
        if source != MPI_PROC_NULL: rank = source
        cdef _p_msg_p2p rmsg = message_p2p_recv(buf, rank)
        cdef MPI_Status *statusp = arg_Status(status)
        with nogil: CHKERR( MPI_Sendrecv_replace(
                rmsg.buf, rmsg.count, rmsg.dtype,
                dest, sendtag, source, recvtag,
                self.ob_mpi, statusp) )

    # Nonblocking Communications
    # --------------------------

    def Isend(self, buf, int dest=0, int tag=0):
        """
        Nonblocking send
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Request request = <Request>Request.__new__(Request)
        with nogil: CHKERR( MPI_Isend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Irecv(self, buf, int source=0, int tag=0):
        """
        Nonblocking receive
        """
        cdef _p_msg_p2p rmsg = message_p2p_recv(buf, source)
        cdef Request request = <Request>Request.__new__(Request)
        with nogil: CHKERR( MPI_Irecv(
            rmsg.buf, rmsg.count, rmsg.dtype,
            source, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = rmsg
        return request

    # Probe
    # -----

    def Probe(self, int source=0, int tag=0, Status status=None):
        """
        Blocking test for a message

        .. note:: This function blocks until the message arrives.
        """
        cdef MPI_Status *statusp = arg_Status(status)
        with nogil: CHKERR( MPI_Probe(
            source, tag, self.ob_mpi, statusp) )

    def Iprobe(self, int source=0, int tag=0, Status status=None):
        """
        Nonblocking test for a message
        """
        cdef int flag = 0
        cdef MPI_Status *statusp = arg_Status(status)
        with nogil: CHKERR( MPI_Iprobe(
            source, tag, self.ob_mpi, &flag, statusp) )
        return <bint>flag

    # Persistent Communication
    # ------------------------

    def Send_init(self, buf, int dest=0, int tag=0):
        """
        Create a persistent request for a standard send
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Prequest request = <Prequest>Prequest.__new__(Prequest)
        with nogil: CHKERR( MPI_Send_init(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Recv_init(self, buf, int source=0, int tag=0):
        """
        Create a persistent request for a receive
        """
        cdef _p_msg_p2p rmsg = message_p2p_recv(buf, source)
        cdef Prequest request = <Prequest>Prequest.__new__(Prequest)
        with nogil: CHKERR( MPI_Recv_init(
            rmsg.buf, rmsg.count, rmsg.dtype,
            source, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = rmsg
        return request

    # Communication Modes
    # -------------------

    # Blocking calls

    def Bsend(self, buf, int dest=0, int tag=0):
        """
        Blocking send in buffered mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        with nogil: CHKERR( MPI_Bsend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi) )

    def Ssend(self, buf, int dest=0, int tag=0):
        """
        Blocking send in synchronous mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        with nogil: CHKERR( MPI_Ssend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi) )

    def Rsend(self, buf, int dest=0, int tag=0):
        """
        Blocking send in ready mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        with nogil: CHKERR( MPI_Rsend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi) )

    # Nonblocking calls

    def Ibsend(self, buf, int dest=0, int tag=0):
        """
        Nonblocking send in buffered mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Request request = <Request>Request.__new__(Request)
        with nogil: CHKERR( MPI_Ibsend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Issend(self, buf, int dest=0, int tag=0):
        """
        Nonblocking send in synchronous mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Request request = <Request>Request.__new__(Request)
        with nogil: CHKERR( MPI_Issend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Irsend(self, buf, int dest=0, int tag=0):
        """
        Nonblocking send in ready mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Request request = <Request>Request.__new__(Request)
        with nogil: CHKERR( MPI_Irsend(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    # Persistent Requests

    def Bsend_init(self, buf, int dest=0, int tag=0):
        """
        Persistent request for a send in buffered mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Prequest request = <Prequest>Prequest.__new__(Prequest)
        with nogil: CHKERR( MPI_Bsend_init(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Ssend_init(self, buf, int dest=0, int tag=0):
        """
        Persistent request for a send in synchronous mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Prequest request = <Prequest>Prequest.__new__(Prequest)
        with nogil: CHKERR( MPI_Ssend_init(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    def Rsend_init(self, buf, int dest=0, int tag=0):
        """
        Persistent request for a send in ready mode
        """
        cdef _p_msg_p2p smsg = message_p2p_send(buf, dest)
        cdef Prequest request = <Prequest>Prequest.__new__(Prequest)
        with nogil: CHKERR( MPI_Rsend_init(
            smsg.buf, smsg.count, smsg.dtype,
            dest, tag, self.ob_mpi, &request.ob_mpi) )
        request.ob_buf = smsg
        return request

    # Collective Communications
    # -------------------------

    # Barrier Synchronization
    # -----------------------

    def Barrier(self):
        """
        Barrier synchronization
        """
        with nogil: CHKERR( MPI_Barrier(self.ob_mpi) )

    # Global Communication Functions
    # ------------------------------

    def Bcast(self, buf, int root=0):
        """
        Broadcast a message from one process
        to all other processes in a group
        """
        cdef _p_msg_cco m = message_cco()
        m.for_bcast(buf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Bcast(
            m.sbuf, m.scount, m.stype,
            root, self.ob_mpi) )

    def Gather(self, sendbuf, recvbuf, int root=0):
        """
        Gather together values from a group of processes
        """
        cdef _p_msg_cco m = message_cco()
        m.for_gather(0, sendbuf, recvbuf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Gather(
            m.sbuf, m.scount, m.stype,
            m.rbuf, m.rcount, m.rtype,
            root, self.ob_mpi) )

    def Gatherv(self, sendbuf, recvbuf, int root=0):
        """
        Gather Vector, gather data to one process from all other
        processes in a group providing different amount of data and
        displacements at the receiving sides
        """
        cdef _p_msg_cco m = message_cco()
        m.for_gather(1, sendbuf, recvbuf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Gatherv(
            m.sbuf, m.scount,             m.stype,
            m.rbuf, m.rcounts, m.rdispls, m.rtype,
            root, self.ob_mpi) )

    def Scatter(self, sendbuf, recvbuf, int root=0):
        """
        Scatter data from one process
        to all other processes in a group
        """
        cdef _p_msg_cco m = message_cco()
        m.for_scatter(0, sendbuf, recvbuf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Scatter(
            m.sbuf, m.scount, m.stype,
            m.rbuf, m.rcount, m.rtype,
            root, self.ob_mpi) )

    def Scatterv(self, sendbuf, recvbuf, int root=0):
        """
        Scatter Vector, scatter data from one process to all other
        processes in a group providing different amount of data and
        displacements at the sending side
        """
        cdef _p_msg_cco m = message_cco()
        m.for_scatter(1, sendbuf, recvbuf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Scatterv(
            m.sbuf, m.scounts, m.sdispls, m.stype,
            m.rbuf, m.rcount,             m.rtype,
            root, self.ob_mpi) )

    def Allgather(self, sendbuf, recvbuf):
        """
        Gather to All, gather data from all processes and
        distribute it to all other processes in a group
        """
        cdef _p_msg_cco m = message_cco()
        m.for_allgather(0, sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Allgather(
            m.sbuf, m.scount, m.stype,
            m.rbuf, m.rcount, m.rtype,
            self.ob_mpi) )

    def Allgatherv(self, sendbuf, recvbuf):
        """
        Gather to All Vector, gather data from all processes and
        distribute it to all other processes in a group providing
        different amount of data and displacements
        """
        cdef _p_msg_cco m = message_cco()
        m.for_allgather(1, sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Allgatherv(
            m.sbuf, m.scount,             m.stype,
            m.rbuf, m.rcounts, m.rdispls, m.rtype,
            self.ob_mpi) )

    def Alltoall(self, sendbuf, recvbuf):
        """
        All to All Scatter/Gather, send data from all to all
        processes in a group
        """
        cdef _p_msg_cco m = message_cco()
        m.for_alltoall(0, sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Alltoall(
            m.sbuf, m.scount, m.stype,
            m.rbuf, m.rcount, m.rtype,
            self.ob_mpi) )

    def Alltoallv(self, sendbuf, recvbuf):
        """
        All to All Scatter/Gather Vector, send data from all to all
        processes in a group providing different amount of data and
        displacements
        """
        cdef _p_msg_cco m = message_cco()
        m.for_alltoall(1, sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Alltoallv(
            m.sbuf, m.scounts, m.sdispls, m.stype,
            m.rbuf, m.rcounts, m.rdispls, m.rtype,
            self.ob_mpi) )

    def Alltoallw(self, sendbuf, recvbuf):
        """
        Generalized All-to-All communication allowing different
        counts, displacements and datatypes for each partner
        """
        raise NotImplementedError # XXX implement!
        cdef void *sbuf = NULL, *rbuf = NULL
        cdef int  *scounts = NULL, *rcounts = NULL
        cdef int  *sdispls = NULL, *rdispls = NULL
        cdef MPI_Datatype *stypes = NULL, *rtypes = NULL
        with nogil: CHKERR( MPI_Alltoallw(
            sbuf, scounts, sdispls, stypes,
            rbuf, rcounts, rdispls, rtypes,
            self.ob_mpi) )


    # Global Reduction Operations
    # ---------------------------

    def Reduce(self, sendbuf, recvbuf, Op op not None=SUM, int root=0):
        """
        Reduce
        """
        cdef _p_msg_cco m = message_cco()
        m.for_reduce(sendbuf, recvbuf, root, self.ob_mpi)
        with nogil: CHKERR( MPI_Reduce(
            m.sbuf, m.rbuf, m.rcount, m.rtype,
            op.ob_mpi, root, self.ob_mpi) )

    def Allreduce(self, sendbuf, recvbuf, Op op not None=SUM):
        """
        All Reduce
        """
        cdef _p_msg_cco m = message_cco()
        m.for_allreduce(sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Allreduce(
            m.sbuf, m.rbuf, m.rcount, m.rtype,
            op.ob_mpi, self.ob_mpi) )

    def Reduce_scatter_block(self, sendbuf, recvbuf,
                             Op op not None=SUM):
        """
        Reduce-Scatter Block (regular, non-vector version)
        """
        cdef _p_msg_cco m = message_cco()
        m.for_reduce_scatter_block(sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Reduce_scatter_block(
            m.sbuf, m.rbuf, m.rcount, m.rtype,
            op.ob_mpi, self.ob_mpi) )

    def Reduce_scatter(self, sendbuf, recvbuf, recvcounts=None,
                       Op op not None=SUM):
        """
        Reduce-Scatter (vector version)
        """
        cdef _p_msg_cco m = message_cco()
        m.for_reduce_scatter(sendbuf, recvbuf,
                             recvcounts, self.ob_mpi)
        with nogil: CHKERR( MPI_Reduce_scatter(
            m.sbuf, m.rbuf, m.rcounts, m.rtype,
            op.ob_mpi, self.ob_mpi) )

    # Tests
    # -----

    def Is_inter(self):
        """
        Test to see if a comm is an intercommunicator
        """
        cdef int flag = 0
        CHKERR( MPI_Comm_test_inter(self.ob_mpi, &flag) )
        return <bint>flag

    property is_inter:
        """is intercommunicator"""
        def __get__(self):
            return self.Is_inter()

    def Is_intra(self):
        """
        Test to see if a comm is an intracommunicator
        """
        return not self.Is_inter()

    property is_intra:
        """is intracommunicator"""
        def __get__(self):
            return self.Is_intra()

    def Get_topology(self):
        """
        Determine the type of topology (if any)
        associated with a communicator
        """
        cdef int topo = MPI_UNDEFINED
        CHKERR( MPI_Topo_test(self.ob_mpi, &topo) )
        return topo

    property topology:
        """communicator topology type"""
        def __get__(self):
            return self.Get_topology()

    # Process Creation and Management
    # -------------------------------

    @classmethod
    def Get_parent(cls):
        """
        Return the parent intercommunicator for this process
        """
        cdef MPI_Comm comm = MPI_COMM_NULL
        with nogil: CHKERR( MPI_Comm_get_parent(&comm) )
        global __COMM_PARENT__
        cdef Intercomm parent = __COMM_PARENT__
        parent.ob_mpi = comm
        return parent

    def Disconnect(self):
        """
        Disconnect from a communicator
        """
        with nogil: CHKERR( MPI_Comm_disconnect(
            &self.ob_mpi) )

    @classmethod
    def Join(cls, int fd):
        """
        Create a intercommunicator by joining
        two processes connected by a socket
        """
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Comm_join(
            fd, &comm.ob_mpi) )
        return comm

    # Attributes
    # ----------

    def Get_attr(self, int keyval):
        """
        Retrieve attribute value by key
        """
        cdef void *attrval = NULL
        cdef int  flag = 0
        CHKERR(MPI_Comm_get_attr(self.ob_mpi, keyval, &attrval, &flag) )
        if not flag: return None
        if attrval == NULL: return 0
        # MPI-1 predefined attribute keyvals
        if ((keyval == <int>MPI_TAG_UB) or
            (keyval == <int>MPI_HOST) or
            (keyval == <int>MPI_IO) or
            (keyval == <int>MPI_WTIME_IS_GLOBAL)):
            return (<int*>attrval)[0]
        # MPI-2 predefined attribute keyvals
        elif ((keyval == <int>MPI_UNIVERSE_SIZE) or
              (keyval == <int>MPI_APPNUM) or
              (keyval == <int>MPI_LASTUSEDCODE)):
            return (<int*>attrval)[0]
        # user-defined attribute keyval
        elif keyval in comm_keyval:
            return <object>attrval
        else:
            return PyLong_FromVoidPtr(attrval)

    def Set_attr(self, int keyval, object attrval):
        """
        Store attribute value associated with a key
        """
        cdef void *ptrval = NULL
        cdef int incref = 0
        if keyval in comm_keyval:
            ptrval = <void*>attrval
            incref = 1
        else:
            ptrval = PyLong_AsVoidPtr(attrval)
            incref = 0
        CHKERR(MPI_Comm_set_attr(self.ob_mpi, keyval, ptrval) )
        if incref: Py_INCREF(attrval)

    def Delete_attr(self, int keyval):
        """
        Delete attribute value associated with a key
        """
        CHKERR(MPI_Comm_delete_attr(self.ob_mpi, keyval) )

    @classmethod
    def Create_keyval(cls, copy_fn=None, delete_fn=None):
        """
        Create a new attribute key for communicators
        """
        cdef int keyval = MPI_KEYVAL_INVALID
        cdef MPI_Comm_copy_attr_function *_copy = comm_attr_copy_fn
        cdef MPI_Comm_delete_attr_function *_del = comm_attr_delete_fn
        cdef void *extra_state = NULL
        CHKERR( MPI_Comm_create_keyval(_copy, _del, &keyval, extra_state) )
        comm_keyval_new(keyval, copy_fn, delete_fn)
        return keyval

    @classmethod
    def Free_keyval(cls, int keyval):
        """
        Free and attribute key for communicators
        """
        cdef int keyval_save = keyval
        CHKERR( MPI_Comm_free_keyval (&keyval) )
        comm_keyval_del(keyval_save)
        return keyval

    # Error handling
    # --------------

    def Get_errhandler(self):
        """
        Get the error handler for a communicator
        """
        cdef Errhandler errhandler = <Errhandler>Errhandler.__new__(Errhandler)
        CHKERR( MPI_Comm_get_errhandler(self.ob_mpi, &errhandler.ob_mpi) )
        return errhandler

    def Set_errhandler(self, Errhandler errhandler not None):
        """
        Set the error handler for a communicator
        """
        CHKERR( MPI_Comm_set_errhandler(self.ob_mpi, errhandler.ob_mpi) )

    def Call_errhandler(self, int errorcode):
        """
        Call the error handler installed on a communicator
        """
        CHKERR( MPI_Comm_call_errhandler(self.ob_mpi, errorcode) )


    def Abort(self, int errorcode=0):
        """
        Terminate MPI execution environment

        .. warning:: This is a direct call, use it with care!!!.
        """
        CHKERR( MPI_Abort(self.ob_mpi, errorcode) )

    # Naming Objects
    # --------------

    def Get_name(self):
        """
        Get the print name for this communicator
        """
        cdef char name[MPI_MAX_OBJECT_NAME+1]
        cdef int nlen = 0
        CHKERR( MPI_Comm_get_name(self.ob_mpi, name, &nlen) )
        return tompistr(name, nlen)

    def Set_name(self, name):
        """
        Set the print name for this communicator
        """
        cdef char *cname = NULL
        name = asmpistr(name, &cname, NULL)
        CHKERR( MPI_Comm_set_name(self.ob_mpi, cname) )

    property name:
        """communicator name"""
        def __get__(self):
            return self.Get_name()
        def __set__(self, value):
            self.Set_name(value)

    # Fortran Handle
    # --------------

    def py2f(self):
        """
        """
        return MPI_Comm_c2f(self.ob_mpi)

    @classmethod
    def f2py(cls, arg):
        """
        """
        cdef Comm comm = <Comm>cls()
        comm.ob_mpi = MPI_Comm_f2c(arg)
        return comm

    # Python Communication
    # --------------------
    #
    def send(self, obj=None, int dest=0, int tag=0):
        """Send"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_send(obj, dest, tag, comm)
    #
    def bsend(self, obj=None, int dest=0, int tag=0):
        """Send in buffered mode"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_bsend(obj, dest, tag, comm)
    #
    def ssend(self, obj=None, int dest=0, int tag=0):
        """Send in synchronous mode"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_ssend(obj, dest, tag, comm)
    #
    def recv(self, obj=None, int source=0, int tag=0, Status status=None):
        """Receive"""
        cdef MPI_Comm comm = self.ob_mpi
        cdef MPI_Status *statusp = arg_Status(status)
        return PyMPI_recv(obj, source, tag, comm, statusp)
    #
    def sendrecv(self,
                 sendobj=None, int dest=0,   int sendtag=0,
                 recvobj=None, int source=0, int recvtag=0,
                 Status status=None):
        """Send and Receive"""
        cdef MPI_Comm comm = self.ob_mpi
        cdef MPI_Status *statusp = arg_Status(status)
        return PyMPI_sendrecv(sendobj, dest,   sendtag,
                              recvobj, source, recvtag,
                              comm, statusp)
    #
    def isend(self, obj=None, int dest=0, int tag=0):
        """Nonblocking send"""
        cdef MPI_Comm comm = self.ob_mpi
        cdef Request request = <Request>Request.__new__(Request)
        request.ob_buf = PyMPI_isend(obj, dest, tag, comm, &request.ob_mpi)
        return request
    #
    def ibsend(self, obj=None, int dest=0, int tag=0):
        """Nonblocking send in buffered mode"""
        cdef MPI_Comm comm = self.ob_mpi
        cdef Request request = <Request>Request.__new__(Request)
        request.ob_buf = PyMPI_ibsend(obj, dest, tag, comm, &request.ob_mpi)
        return request
    #
    def issend(self, obj=None, int dest=0, int tag=0):
        """Nonblocking send in synchronous mode"""
        cdef MPI_Comm comm = self.ob_mpi
        cdef Request request = <Request>Request.__new__(Request)
        request.ob_buf = PyMPI_issend(obj, dest, tag, comm, &request.ob_mpi)
        return request
    #
    def barrier(self):
        "Barrier"
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_barrier(comm)
    #
    def bcast(self, obj=None, int root=0):
        """Broadcast"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_bcast(obj, root, comm)
    #
    def gather(self, sendobj=None, recvobj=None, int root=0):
        """Gather"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_gather(sendobj, recvobj, root, comm)
    #
    def scatter(self, sendobj=None, recvobj=None, int root=0):
        """Scatter"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_scatter(sendobj, recvobj, root, comm)
    #
    def allgather(self, sendobj=None, recvobj=None):
        """Gather to All"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_allgather(sendobj, recvobj, comm)
    #
    def alltoall(self, sendobj=None, recvobj=None):
        """All to All Scatter/Gather"""
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_alltoall(sendobj, recvobj, comm)
    #
    def reduce(self, sendobj=None, recvobj=None, op=SUM, int root=0):
        """Reduce"""
        if op is None: op = SUM
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_reduce(sendobj, recvobj, op, root, comm)
    #
    def allreduce(self, sendobj=None, recvobj=None, op=SUM):
        """Reduce to All"""
        if op is None: op = SUM
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_allreduce(sendobj, recvobj, op, comm)


cdef class Intracomm(Comm):

    """
    Intracommunicator
    """

    def __cinit__(self, Comm comm=None):
        cdef int inter = 0
        if self.ob_mpi != MPI_COMM_NULL:
            CHKERR( MPI_Comm_test_inter(self.ob_mpi, &inter) )
            if inter: raise TypeError(
                "expecting an intracommunicator")

    # Communicator Constructors
    # -------------------------

    def Dup(self):
        """
        Duplicate an existing intracommunicator
        """
        cdef Intracomm comm = <Intracomm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(self.ob_mpi, &comm.ob_mpi) )
        return comm

    def Create(self, Group group not None):
        """
        Create intracommunicator from group
        """
        cdef Intracomm comm = <Intracomm>type(self)()
        with nogil: CHKERR( MPI_Comm_create(
            self.ob_mpi, group.ob_mpi, &comm.ob_mpi) )
        return comm

    def Split(self, int color=0, int key=0):
        """
        Split intracommunicator by color and key
        """
        cdef Intracomm comm = <Intracomm>type(self)()
        with nogil: CHKERR( MPI_Comm_split(
            self.ob_mpi, color, key, &comm.ob_mpi) )
        return comm

    def Create_cart(self, dims, periods=None, bint reorder=False):
        """
        Create cartesian communicator
        """
        cdef int ndims = 0, *idims = NULL
        dims = getarray_int(dims, &ndims, &idims)
        if periods is None: periods = [False] * ndims
        cdef int *iperiods = NULL
        periods = chkarray_int(periods, ndims, &iperiods)
        #
        cdef Cartcomm comm = <Cartcomm>Cartcomm.__new__(Cartcomm)
        with nogil: CHKERR( MPI_Cart_create(
            self.ob_mpi, ndims, idims, iperiods, reorder, &comm.ob_mpi) )
        return comm

    def Create_graph(self, index, edges, bint reorder=False):
        """
        Create graph communicator
        """
        cdef int nnodes = 0, *iindex = NULL
        index = getarray_int(index, &nnodes, &iindex)
        cdef int nedges = 0, *iedges = NULL
        edges = getarray_int(edges, &nedges, &iedges)
        # extension: 'standard' adjacency arrays
        if iindex[0]==0 and iindex[nnodes-1]==nedges:
            nnodes -= 1; iindex += 1;
        #
        cdef Graphcomm comm = <Graphcomm>Graphcomm.__new__(Graphcomm)
        with nogil: CHKERR( MPI_Graph_create(
            self.ob_mpi, nnodes, iindex, iedges, reorder, &comm.ob_mpi) )
        return comm

    def Create_dist_graph_adjacent(self, sources, destinations,
                                   sourceweights=None, destweights=None,
                                   Info info=INFO_NULL, bint reorder=False):
        """
        Create distributed graph communicator
        """
        cdef int indegree  = 0, *isource = NULL
        cdef int outdegree = 0, *idest   = NULL
        cdef int *isourceweight = MPI_UNWEIGHTED
        cdef int *idestweight   = MPI_UNWEIGHTED
        if sources is not None:
            sources = getarray_int(sources, &indegree, &isource)
        if sourceweights is not None:
            sourceweights = chkarray_int(
                sourceweights, indegree, &isourceweight)
        if destinations is not None:
            destinations = getarray_int(destinations, &outdegree, &idest)
        if destweights is not None:
            destweights = chkarray_int(destweights, outdegree, &idestweight)
        cdef MPI_Info cinfo = arg_Info(info)
        #
        cdef Distgraphcomm comm = \
            <Distgraphcomm>Distgraphcomm.__new__(Distgraphcomm)
        CHKERR( MPI_Dist_graph_create_adjacent(
                self.ob_mpi,
                indegree,  isource, isourceweight,
                outdegree, idest,   idestweight,
                cinfo, reorder, &comm.ob_mpi) )
        return comm

    def Create_dist_graph(self, sources, degrees, destinations, weights=None,
                          Info info=INFO_NULL, bint reorder=False):
        """
        Create distributed graph communicator
        """
        cdef int nv = 0, ne = 0, i = 0
        cdef int *isource = NULL, *idegree = NULL,
        cdef int *idest = NULL, *iweight = MPI_UNWEIGHTED
        sources = getarray_int(sources, &nv, &isource)
        degrees = chkarray_int(degrees,  nv, &idegree)
        for i from 0 <= i < nv: ne += idegree[i]
        destinations = chkarray_int(destinations, ne, &idest)
        if weights is not None:
            weights = chkarray_int(weights, ne, &iweight)
        cdef MPI_Info cinfo = arg_Info(info)
        #
        cdef Distgraphcomm comm = \
            <Distgraphcomm>Distgraphcomm.__new__(Distgraphcomm)
        CHKERR( MPI_Dist_graph_create(
                self.ob_mpi,
                nv, isource, idegree, idest, iweight,
                cinfo, reorder, &comm.ob_mpi) )
        return comm

    def Create_intercomm(self,
                         int local_leader,
                         Intracomm peer_comm not None,
                         int remote_leader,
                         int tag=0):
        """
        Create intercommunicator
        """
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Intercomm_create(
            self.ob_mpi, local_leader,
            peer_comm.ob_mpi, remote_leader,
            tag, &comm.ob_mpi) )
        return comm

    # Global Reduction Operations
    # ---------------------------

    # Inclusive Scan

    def Scan(self, sendbuf, recvbuf, Op op not None=SUM):
        """
        Inclusive Scan
        """
        cdef _p_msg_cco m = message_cco()
        m.for_scan(sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Scan(
            m.sbuf, m.rbuf, m.rcount, m.rtype,
            op.ob_mpi, self.ob_mpi) )

    # Exclusive Scan

    def Exscan(self, sendbuf, recvbuf, Op op not None=SUM):
        """
        Exclusive Scan
        """
        cdef _p_msg_cco m = message_cco()
        m.for_exscan(sendbuf, recvbuf, self.ob_mpi)
        with nogil: CHKERR( MPI_Exscan(
            m.sbuf, m.rbuf, m.rcount, m.rtype,
            op.ob_mpi, self.ob_mpi) )

    # Python Communication
    #
    def scan(self, sendobj=None, recvobj=None, op=SUM):
        """Inclusive Scan"""
        if op is None: op = SUM
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_scan(sendobj, recvobj, op, comm)
    #
    def exscan(self, sendobj=None, recvobj=None, op=SUM):
        """Exclusive Scan"""
        if op is None: op = SUM
        cdef MPI_Comm comm = self.ob_mpi
        return PyMPI_exscan(sendobj, recvobj, op, comm)


    # Establishing Communication
    # --------------------------

    # Starting Processes

    def Spawn(self, command, args=None, int maxprocs=1,
              Info info=INFO_NULL, int root=0, errcodes=None):
        """
        Spawn instances of a single MPI application
        """
        cdef char *cmd = NULL
        cdef char **argv = MPI_ARGV_NULL
        cdef MPI_Info cinfo = arg_Info(info)
        cdef int *ierrcodes = MPI_ERRCODES_IGNORE
        #
        cdef int rank = MPI_UNDEFINED
        CHKERR( MPI_Comm_rank(self.ob_mpi, &rank) )
        cdef tmp1, tmp2
        if root == rank:
            command = asmpistr(command, &cmd, NULL)
            if args is not None:
                tmp1 = asarray_argv(args, &argv)
        if errcodes is not None:
            tmp2 = newarray_int(maxprocs, &ierrcodes)
        #
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Comm_spawn(
            cmd, argv, maxprocs, cinfo, root,
            self.ob_mpi, &comm.ob_mpi, ierrcodes) )
        #
        cdef int i=0
        if errcodes is not None:
            errcodes[:] = [ierrcodes[i] for i from 0<=i<maxprocs]
        #
        return comm

    def Spawn_multiple(self, command, args=None, maxprocs=None,
                       info=INFO_NULL, int root=0, errcodes=None):
        """
        Spawn instances of multiple MPI applications
        """
        cdef int count = 0
        cdef char **cmds = NULL
        cdef char ***argvs = MPI_ARGVS_NULL
        cdef MPI_Info *infos = NULL
        cdef int *imaxprocs = NULL
        cdef int *ierrcodes = MPI_ERRCODES_IGNORE
        #
        cdef int rank = MPI_UNDEFINED
        CHKERR( MPI_Comm_rank(self.ob_mpi, &rank) )
        cdef object tmp1, tmp2, tmp3, tmp4, tmp5
        cdef Py_ssize_t i=0, n=0
        if root == rank:
            count = <int>len(command)
            tmp1 = asarray_str(command, count, &cmds)
            tmp2 = asarray_argvs(args, count, &argvs)
            tmp3 = asarray_nprocs(maxprocs, count, &imaxprocs)
            tmp4 = asarray_Info(info, count, &infos)
        if errcodes is not None:
            if root != rank:
                count = <int>len(maxprocs)
                tmp3 = asarray_nprocs(maxprocs, count, &imaxprocs)
            for i from 0 <= i < count:
                n += imaxprocs[i]
            tmp5 = newarray_int(n, &ierrcodes)
        #
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Comm_spawn_multiple(
            count, cmds, argvs, imaxprocs, infos, root,
            self.ob_mpi, &comm.ob_mpi, ierrcodes) )
        #
        cdef Py_ssize_t j=0, p=0
        if errcodes is not None:
            errcodes[:] = [[]] * count
            for i from 0 <= i < count:
                n = imaxprocs[i]
                errcodes[i] = \
                    [ierrcodes[j] for j from p<=j<(p+n)]
                p += n
        #
        return comm


    # Server Routines

    def Accept(self, port_name, Info info=INFO_NULL, int root=0):
        """
        Accept a request to form a new intercommunicator
        """
        cdef char *cportname = NULL
        cdef MPI_Info cinfo = MPI_INFO_NULL
        cdef int rank = MPI_UNDEFINED
        CHKERR( MPI_Comm_rank(self.ob_mpi, &rank) )
        if root == rank:
            port_name = asmpistr(port_name, &cportname, NULL)
            cinfo = arg_Info(info)
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Comm_accept(
            cportname, cinfo, root,
            self.ob_mpi, &comm.ob_mpi) )
        return comm

    # Client Routines

    def Connect(self, port_name, Info info=INFO_NULL, int root=0):
        """
        Make a request to form a new intercommunicator
        """
        cdef char *cportname = NULL
        cdef MPI_Info cinfo = MPI_INFO_NULL
        cdef int rank = MPI_UNDEFINED
        CHKERR( MPI_Comm_rank(self.ob_mpi, &rank) )
        if root == rank:
            port_name = asmpistr(port_name, &cportname, NULL)
            cinfo = arg_Info(info)
        cdef Intercomm comm = <Intercomm>Intercomm.__new__(Intercomm)
        with nogil: CHKERR( MPI_Comm_connect(
            cportname, cinfo, root,
            self.ob_mpi, &comm.ob_mpi) )
        return comm


cdef class Cartcomm(Intracomm):

    """
    Cartesian topology intracommunicator
    """

    def __cinit__(self, Comm comm=None):
        cdef int topo = MPI_CART
        if self.ob_mpi != MPI_COMM_NULL:
            CHKERR( MPI_Topo_test(self.ob_mpi, &topo) )
            if topo != MPI_CART: raise TypeError(
                "expecting a Cartesian communicator")

    # Communicator Constructors
    # -------------------------

    def Dup(self):
        """
        Duplicate an existing communicator
        """
        cdef Cartcomm comm = <Cartcomm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(self.ob_mpi, &comm.ob_mpi) )
        return comm

    # Cartesian Inquiry Functions
    # ---------------------------

    def Get_dim(self):
        """
        Return number of dimensions
        """
        cdef int dim = 0
        CHKERR( MPI_Cartdim_get(self.ob_mpi, &dim) )
        return dim

    property dim:
        """number of dimensions"""
        def __get__(self):
            return self.Get_dim()

    property ndim:
        """number of dimensions"""
        def __get__(self):
            return self.Get_dim()

    def Get_topo(self):
        """
        Return information on the cartesian topology
        """
        cdef int ndim = 0
        CHKERR( MPI_Cartdim_get(self.ob_mpi, &ndim) )
        cdef int *idims = NULL
        cdef tmp1 = newarray_int(ndim, &idims)
        cdef int *iperiods = NULL
        cdef tmp2 = newarray_int(ndim, &iperiods)
        cdef int *icoords = NULL
        cdef tmp3 = newarray_int(ndim, &icoords)
        CHKERR( MPI_Cart_get(self.ob_mpi, ndim, idims, iperiods, icoords) )
        cdef int i = 0
        cdef object dims    = [idims[i]    for i from 0 <= i < ndim]
        cdef object periods = [iperiods[i] for i from 0 <= i < ndim]
        cdef object coords  = [icoords[i]  for i from 0 <= i < ndim]
        return (dims, periods, coords)

    property topo:
        """topology information"""
        def __get__(self):
            return self.Get_topo()

    property dims:
        """dimensions"""
        def __get__(self):
            return self.Get_topo()[0]

    property periods:
        """periodicity"""
        def __get__(self):
            return self.Get_topo()[1]

    property coords:
        """coordinates"""
        def __get__(self):
            return self.Get_topo()[2]


    # Cartesian Translator Functions
    # ------------------------------

    def Get_cart_rank(self, coords):
        """
        Translate logical coordinates to ranks
        """
        cdef int ndim = 0, *icoords = NULL
        CHKERR( MPI_Cartdim_get( self.ob_mpi, &ndim) )
        coords = chkarray_int(coords, ndim, &icoords)
        cdef int rank = MPI_PROC_NULL
        CHKERR( MPI_Cart_rank(self.ob_mpi, icoords, &rank) )
        return rank

    def Get_coords(self, int rank):
        """
        Translate ranks to logical coordinates
        """
        cdef int ndim = 0, *icoords = NULL
        CHKERR( MPI_Cartdim_get(self.ob_mpi, &ndim) )
        cdef object coords = newarray_int(ndim, &icoords)
        CHKERR( MPI_Cart_coords(self.ob_mpi, rank, ndim, icoords) )
        return coords

    # Cartesian Shift Function
    # ------------------------

    def Shift(self, int direction, int disp):
        """
        Return a tuple (source,dest) of process ranks
        for data shifting with Comm.Sendrecv()
        """
        cdef int source = MPI_PROC_NULL, dest = MPI_PROC_NULL
        CHKERR( MPI_Cart_shift(self.ob_mpi, direction, disp, &source, &dest) )
        return (source, dest)

    # Cartesian Partition Function
    # ----------------------------

    def Sub(self, remain_dims):
        """
        Return cartesian communicators
        that form lower-dimensional subgrids
        """
        cdef int ndim = 0, *iremdims = NULL
        CHKERR( MPI_Cartdim_get(self.ob_mpi, &ndim) )
        remain_dims = chkarray_int(remain_dims, ndim, &iremdims)
        cdef Cartcomm comm = <Cartcomm>Cartcomm.__new__(Cartcomm)
        with nogil: CHKERR( MPI_Cart_sub(self.ob_mpi, iremdims, &comm.ob_mpi) )
        return comm


    # Cartesian Low-Level Functions
    # -----------------------------

    def Map(self, dims, periods=None):
        """
        Return an optimal placement for the
        calling process on the physical machine
        """
        cdef int ndims = 0, *idims = NULL, *iperiods = NULL
        dims = getarray_int(dims, &ndims, &idims)
        if periods is None: periods = [False] * ndims
        periods = chkarray_int(periods, ndims, &iperiods)
        cdef int rank = MPI_PROC_NULL
        CHKERR( MPI_Cart_map(self.ob_mpi, ndims, idims, iperiods, &rank) )
        return rank


# Cartesian Convenience Function

def Compute_dims(int nnodes, dims):
    """
    Return a balanced distribution of
    processes per coordinate direction
    """
    cdef int ndims=0, *idims = NULL
    try:
        ndims = <int>len(dims)
    except:
        ndims = dims
        dims = [0] * ndims
    dims = chkarray_int(dims, ndims, &idims)
    CHKERR( MPI_Dims_create(nnodes, ndims, idims) )
    return dims


cdef class Graphcomm(Intracomm):

    """
    General graph topology intracommunicator
    """

    def __cinit__(self, Comm comm=None):
        cdef int topo = MPI_GRAPH
        if self.ob_mpi != MPI_COMM_NULL:
            CHKERR( MPI_Topo_test(self.ob_mpi, &topo) )
            if topo != MPI_GRAPH: raise TypeError(
                "expecting a general graph communicator")

    # Communicator Constructors
    # -------------------------

    def Dup(self):
        """
        Duplicate an existing communicator
        """
        cdef Graphcomm comm = <Graphcomm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(
            self.ob_mpi, &comm.ob_mpi) )
        return comm

    # Graph Inquiry Functions
    # -----------------------

    def Get_dims(self):
        """
        Return the number of nodes and edges
        """
        cdef int nnodes = 0, nedges = 0
        CHKERR( MPI_Graphdims_get(self.ob_mpi, &nnodes, &nedges) )
        return (nnodes, nedges)

    property dims:
        """number of nodes and edges"""
        def __get__(self):
            return self.Get_topo()

    property nnodes:
        """number of nodes"""
        def __get__(self):
            return self.Get_topo()[0]

    property nedges:
        """number of edges"""
        def __get__(self):
            return self.Get_topo()[1]

    def Get_topo(self):
        """
        Return index and edges
        """
        cdef int nindex = 0, nedges = 0
        CHKERR( MPI_Graphdims_get( self.ob_mpi, &nindex, &nedges) )
        cdef int *iindex = NULL
        cdef tmp1 = newarray_int(nindex, &iindex)
        cdef int *iedges = NULL
        cdef tmp2 = newarray_int(nedges, &iedges)
        CHKERR( MPI_Graph_get(self.ob_mpi, nindex, nedges, iindex, iedges) )
        cdef int i = 0
        cdef object index = [iindex[i] for i from 0 <= i < nindex]
        cdef object edges = [iedges[i] for i from 0 <= i < nedges]
        return (index, edges)

    property topo:
        """topology information"""
        def __get__(self):
            return self.Get_topo()

    property index:
        """index"""
        def __get__(self):
            return self.Get_topo()[0]

    property edges:
        """edges"""
        def __get__(self):
            return self.Get_topo()

    # Graph Information Functions
    # ---------------------------

    def Get_neighbors_count(self, int rank):
        """
        Return number of neighbors of a process
        """
        cdef int nneighbors = 0
        CHKERR( MPI_Graph_neighbors_count(self.ob_mpi, rank, &nneighbors) )
        return nneighbors

    property nneighbors:
        """number of neighbors"""
        def __get__(self):
            cdef int rank = self.Get_rank()
            return self.Get_neighbors_count(rank)

    def Get_neighbors(self, int rank):
        """
        Return list of neighbors of a process
        """
        cdef int nneighbors = 0
        with nogil: CHKERR( MPI_Graph_neighbors_count(
            self.ob_mpi, rank, &nneighbors) )
        cdef int *ineighbors = NULL
        cdef tmp = newarray_int(nneighbors, &ineighbors)
        CHKERR( MPI_Graph_neighbors(self.ob_mpi, rank, nneighbors, ineighbors) )
        cdef int i = 0
        cdef object neighbors = [ineighbors[i] for i from 0 <= i < nneighbors]
        return neighbors

    property neighbors:
        """neighbors"""
        def __get__(self):
            cdef int rank = self.Get_rank()
            return self.Get_neighbors(rank)

    # Graph Low-Level Functions
    # -------------------------

    def Map(self, index, edges):
        """
        Return an optimal placement for the
        calling process on the physical machine
        """
        cdef int nnodes = 0, *iindex = NULL
        index = getarray_int(index, &nnodes, &iindex)
        cdef int nedges = 0, *iedges = NULL
        edges = getarray_int(edges, &nedges, &iedges)
        # extension: accept more 'standard' adjacency arrays
        if iindex[0]==0 and iindex[nnodes-1]==nedges:
            nnodes -= 1; iindex += 1;
        cdef int rank = MPI_PROC_NULL
        CHKERR( MPI_Graph_map(self.ob_mpi, nnodes, iindex, iedges, &rank) )
        return rank


cdef class Distgraphcomm(Intracomm):

    """
    Distributed graph topology intracommunicator
    """

    def __cinit__(self, Comm comm=None):
        cdef int topo = MPI_DIST_GRAPH
        if self.ob_mpi != MPI_COMM_NULL:
            CHKERR( MPI_Topo_test(self.ob_mpi, &topo) )
            if topo != MPI_DIST_GRAPH: raise TypeError(
                "expecting a distributed graph communicator")

    # Communicator Constructors
    # -------------------------

    def Dup(self):
        """
        Duplicate an existing communicator
        """
        cdef Distgraphcomm comm = <Distgraphcomm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(
            self.ob_mpi, &comm.ob_mpi) )
        return comm

    # Topology Inquiry Functions
    # --------------------------

    def Get_dist_neighbors_count(self):
        """
        Return adjacency information for a distributed graph topology
        """
        cdef int indegree = 0
        cdef int outdegree = 0
        cdef int weighted = 0
        CHKERR( MPI_Dist_graph_neighbors_count(
                self.ob_mpi, &indegree, &outdegree, &weighted) )
        return (indegree, outdegree, <bint>weighted)

    def Get_dist_neighbors(self):
        """
        Return adjacency information for a distributed graph topology
        """
        cdef int maxindegree = 0, maxoutdegree = 0, weighted = 0
        CHKERR( MPI_Dist_graph_neighbors_count(
                self.ob_mpi, &maxindegree, &maxoutdegree, &weighted) )
        #
        cdef int *sources = NULL, *destinations = NULL
        cdef int *sourceweights = MPI_UNWEIGHTED
        cdef int *destweights   = MPI_UNWEIGHTED
        cdef tmp1, tmp2, tmp3, tmp4
        tmp1 = newarray_int(maxindegree,  &sources)
        tmp2 = newarray_int(maxoutdegree, &destinations)
        cdef int i = 0
        if weighted:
            tmp3 = newarray_int(maxindegree,  &sourceweights)
            for i from 0 <= i < maxindegree:  sourceweights[i] = 1
            tmp4 = newarray_int(maxoutdegree, &destweights)
            for i from 0 <= i < maxoutdegree: destweights[i]   = 1
        #
        CHKERR( MPI_Dist_graph_neighbors(
                self.ob_mpi,
                maxindegree,  sources,      sourceweights,
                maxoutdegree, destinations, destweights) )
        #
        cdef object src = [sources[i]      for i from 0 <= i < maxindegree]
        cdef object dst = [destinations[i] for i from 0 <= i < maxoutdegree]
        if not weighted: return (src, dst, None)
        #
        cdef object sw = [sourceweights[i] for i from 0 <= i < maxindegree]
        cdef object dw = [destweights[i]   for i from 0 <= i < maxoutdegree]
        return (src, dst, (sw, dw))


cdef class Intercomm(Comm):

    """
    Intercommunicator
    """

    def __cinit__(self, Comm comm=None):
        cdef int inter = 1
        if self.ob_mpi != MPI_COMM_NULL:
            CHKERR( MPI_Comm_test_inter(self.ob_mpi, &inter) )
            if not inter: raise TypeError(
                "expecting an intercommunicator")

    # Intercommunicator Accessors
    # ---------------------------

    def Get_remote_group(self):
        """
        Access the remote group associated
        with the inter-communicator
        """
        cdef Group group = <Group>Group.__new__(Group)
        CHKERR( MPI_Comm_remote_group(self.ob_mpi, &group.ob_mpi) )
        return group

    property remote_group:
        """remote group"""
        def __get__(self):
            return self.Get_remote_group()

    def Get_remote_size(self):
        """
        Intercommunicator remote size
        """
        cdef int size = -1
        CHKERR( MPI_Comm_remote_size(self.ob_mpi, &size) )
        return size

    property remote_size:
        """number of remote processes"""
        def __get__(self):
            return self.Get_remote_size()

    # Communicator Constructors
    # -------------------------

    def Dup(self):
        """
        Duplicate an existing intercommunicator
        """
        cdef Intercomm comm = <Intercomm>type(self)()
        with nogil: CHKERR( MPI_Comm_dup(self.ob_mpi, &comm.ob_mpi) )
        return comm

    def Create(self, Group group not None):
        """
        Create intercommunicator from group
        """
        cdef Intercomm comm = <Intercomm>type(self)()
        with nogil: CHKERR( MPI_Comm_create(
            self.ob_mpi, group.ob_mpi, &comm.ob_mpi) )
        return comm

    def Split(self, int color=0, int key=0):
        """
        Split intercommunicator by color and key
        """
        cdef Intercomm comm = <Intercomm>type(self)()
        with nogil: CHKERR( MPI_Comm_split(
            self.ob_mpi, color, key, &comm.ob_mpi) )
        return comm

    def Merge(self, bint high=False):
        """
        Merge intercommunicator
        """
        cdef Intracomm comm = <Intracomm>Intracomm.__new__(Intracomm)
        with nogil: CHKERR( MPI_Intercomm_merge(
            self.ob_mpi, high, &comm.ob_mpi) )
        return comm



cdef Comm      __COMM_NULL__   = new_Comm      ( MPI_COMM_NULL  )
cdef Intracomm __COMM_SELF__   = new_Intracomm ( MPI_COMM_SELF  )
cdef Intracomm __COMM_WORLD__  = new_Intracomm ( MPI_COMM_WORLD )
cdef Intercomm __COMM_PARENT__ = new_Intercomm ( MPI_COMM_NULL  )


# Predefined communicators
# ------------------------

COMM_NULL =  __COMM_NULL__   #: Null communicator handle
COMM_SELF  = __COMM_SELF__   #: Self communicator handle
COMM_WORLD = __COMM_WORLD__  #: World communicator handle


# Buffer Allocation and Usage
# ---------------------------

BSEND_OVERHEAD = MPI_BSEND_OVERHEAD
#: Upper bound of memory overhead for sending in buffered mode

def Attach_buffer(memory):
    """
    Attach a user-provided buffer for
    sending in buffered mode
    """
    cdef void *base = NULL
    cdef int size = 0
    attach_buffer(memory, &base, &size)
    with nogil: CHKERR( MPI_Buffer_attach(base, size) )

def Detach_buffer():
    """
    Remove an existing attached buffer
    """
    cdef void *base = NULL
    cdef int size = 0
    with nogil: CHKERR( MPI_Buffer_detach(&base, &size) )
    return detach_buffer(base, size)


# --------------------------------------------------------------------
# [5] Process Creation and Management
# --------------------------------------------------------------------

# [5.4.2] Server Routines
# -----------------------

def Open_port(Info info=INFO_NULL):
    """
    Return an address that can be used to establish
    connections between groups of MPI processes
    """
    cdef MPI_Info cinfo = arg_Info(info)
    cdef char cportname[MPI_MAX_PORT_NAME+1]
    with nogil: CHKERR( MPI_Open_port(cinfo, cportname) )
    cportname[MPI_MAX_PORT_NAME] = 0 # just in case
    return mpistr(cportname)

def Close_port(port_name):
    """
    Close a port
    """
    cdef char *cportname = NULL
    port_name = asmpistr(port_name, &cportname, NULL)
    with nogil: CHKERR( MPI_Close_port(cportname) )

# [5.4.4] Name Publishing
# -----------------------

def Publish_name(service_name, Info info, port_name):
    """
    Publish a service name
    """
    cdef char *csrvcname = NULL
    service_name = asmpistr(service_name, &csrvcname, NULL)
    cdef char *cportname = NULL
    port_name = asmpistr(port_name, &cportname, NULL)
    cdef MPI_Info cinfo = arg_Info(info)
    with nogil: CHKERR( MPI_Publish_name(csrvcname, cinfo, cportname) )

def Unpublish_name(service_name, Info info, port_name):
    """
    Unpublish a service name
    """
    cdef char *csrvcname = NULL
    service_name = asmpistr(service_name, &csrvcname, NULL)
    cdef char *cportname = NULL
    port_name = asmpistr(port_name, &cportname, NULL)
    cdef MPI_Info cinfo = arg_Info(info)
    with nogil: CHKERR( MPI_Unpublish_name(csrvcname, cinfo, cportname) )

def Lookup_name(service_name, Info info=INFO_NULL):
    """
    Lookup a port name given a service name
    """
    cdef char *csrvcname = NULL
    service_name = asmpistr(service_name, &csrvcname, NULL)
    cdef MPI_Info cinfo = arg_Info(info)
    cdef char cportname[MPI_MAX_PORT_NAME+1]
    with nogil: CHKERR( MPI_Lookup_name(csrvcname, cinfo, cportname) )
    cportname[MPI_MAX_PORT_NAME] = 0 # just in case
    return mpistr(cportname)
