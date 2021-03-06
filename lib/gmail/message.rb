module Gmail
  class Message
    PREFETCH_ATTRS = ["UID", "ENVELOPE", "BODY.PEEK[]", "FLAGS", "X-GM-LABELS", "X-GM-MSGID", "X-GM-THRID"]

    # Raised when given label doesn't exists.
    class NoLabelError < Exception; end

    def initialize(mailbox, uid, _attrs = nil)
      @uid     = uid
      @mailbox = mailbox
      @gmail   = mailbox.instance_variable_get("@gmail") if mailbox  # UGLY
      @_attrs  = _attrs
    end

    def uid
      @uid ||= fetch("UID")
    end

    def msg_id
      @msg_id ||= fetch("X-GM-MSGID")
    end
    alias_method :message_id, :msg_id

    def thr_id
      @thr_id ||= fetch("X-GM-THRID")
    end
    alias_method :thread_id, :thr_id

    def envelope
      @envelope ||= fetch("ENVELOPE")
    end

    def message
      @message ||= Mail.new(fetch("BODY[]"))
    end
    alias_method :raw_message, :message

    def flags
      @flags ||= fetch("FLAGS")
    end

    def labels
      @labels ||= fetch("X-GM-LABELS")
    end

    # Mark message with given flag.
    def flag(name)
      !!@gmail.mailbox(@mailbox.name) do
        @gmail.conn.uid_store(uid, "+FLAGS", [name])
        clear_cached_attributes
      end
    end

    # Unmark message.
    def unflag(name)
      !!@gmail.mailbox(@mailbox.name) do
        @gmail.conn.uid_store(uid, "-FLAGS", [name])
        clear_cached_attributes
      end
    end

    # Do commonly used operations on message.
    def mark(flag)
      case flag
      when :read    then read!
      when :unread  then unread!
      when :deleted then delete!
      when :spam    then spam!
      else
        flag(flag)
      end
    end

    # Check whether message is read
    def read?
      flags.include?(:Seen)
    end

    # Mark as read.
    def read!
      flag(:Seen)
    end

    # Mark as unread.
    def unread!
      unflag(:Seen)
    end

    # Check whether message is starred
    def starred?
      flags.include?(:Flagged)
    end

    # Mark message with star.
    def star!
      flag(:Flagged)
    end

    # Remove message from list of starred.
    def unstar!
      unflag(:Flagged)
    end

    # Marking as spam is done by adding the `\Spam` label. To undo this,
    # you just re-apply the `\Inbox` label (see `#unspam!`)
    def spam!
      add_label("\\Spam")
    end

    # Deleting is done by adding the `\Trash` label. To undo this,
    # you just re-apply the `\Inbox` label (see `#undelete!`)
    def delete!
      add_label("\\Trash")
    end

    #It seems like this should work with:
    #@gmail.mailbox('[Gmail]/All Mail').emails(:message_id =>  id)
    #But that code returns all e-mails, not just the one with matching id.
    #This code is slow, but functional even when the user is in Inbox.
    def locate_in_all_mail
      @gmail.('[Gmail]/All Mail').emails.select { |x| x.message_id == message_id }[0]
    end

    def archive!
      locate_in_all_mail.remove_label("\\Inbox") if @mailbox == "INBOX"
      remove_label("\\Inbox")
    end

    def unarchive!
      add_label("\\Inbox")
    end
    alias_method :unspam!, :unarchive!
    alias_method :undelete!, :unarchive!

    # Move to given box and delete from others.
    # Apply a given label and optionally remove one.
    # TODO: We should probably deprecate this method. It doesn't really add a lot
    #       of value, especially since the concept of "moving" a message from one
    #       label to another doesn't totally make sense in the Gmail world.
    def move_to(name, from = nil)
      add_label(name)
      remove_label(from) if from
    end
    alias_method :move, :move_to
    alias_method :move!, :move_to
    alias_method :move_to!, :move_to

    # Use Gmail IMAP Extensions to add a Label to an email
    def add_label(name)
      @gmail.mailbox(@mailbox.name) do
        @gmail.conn.uid_store(uid, "+X-GM-LABELS", [Net::IMAP.encode_utf7(name.to_s)])
        clear_cached_attributes
      end
    end
    alias_method :label, :add_label
    alias_method :label!, :add_label
    alias_method :add_label!, :add_label

    # Use Gmail IMAP Extensions to remove a Label from an email
    def remove_label(name)
      @gmail.mailbox(@mailbox.name) do
        @gmail.conn.uid_store(uid, "-X-GM-LABELS", [Net::IMAP.encode_utf7(name.to_s)])
        clear_cached_attributes
      end
    end
    alias_method :remove_label!, :remove_label

    def inspect
      "#<Gmail::Message#{'0x%04x' % (object_id << 1)} mailbox=#{@mailbox.name}#{' uid=' + @uid.to_s if @uid}#{' message_id=' + @msg_id.to_s if @msg_id}>"
    end

    def method_missing(meth, *args, &block)
      # Delegate rest directly to the message.
      if envelope.respond_to?(meth)
        envelope.send(meth, *args, &block)
      elsif message.respond_to?(meth)
        message.send(meth, *args, &block)
      else
        super(meth, *args, &block)
      end
    end

    def respond_to?(meth, *args, &block)
      if envelope.respond_to?(meth)
        return true
      elsif message.respond_to?(meth)
        return true
      else
        super(meth, *args, &block)
      end
    end

    private

    def clear_cached_attributes
      @_attrs   = nil
      @msg_id   = nil
      @thr_id   = nil
      @envelope = nil
      @message  = nil
      @flags    = nil
      @labels   = nil
    end

    def fetch(value)
      @_attrs ||= begin
        @gmail.mailbox(@mailbox.name) do
          @gmail.conn.uid_fetch(uid, PREFETCH_ATTRS)[0]
        end
      end
      @_attrs.attr[value]
    end
  end # Message
end # Gmail
